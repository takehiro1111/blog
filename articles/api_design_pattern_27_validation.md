---
title: "[Go]APIデザインパターン 27: リクエストの検証（使う/使わないの前後比較）"
emoji: "📘"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Go", "API", "設計", "デザインパターン"]
published: false
---
![](/images/go/go_logo.png =450x)

## 本記事の内容
- 『APIデザイン・パターン』(JJ Geewax 著、マイナビ出版) の第 27 章「リクエストの検証」を、Go で書き直しながら読んだメモです
- パターンを使わない実装と使う実装を同じ手順で動かして、何が変わるかを出力で確かめます
- コードは Go 1.22 以降の `net/http` と標準ライブラリだけで動きます
- シリーズの目次は「[Go]APIデザインパターン 00: 目次と、パターンを使わないとどうなるか」にあります

## 1. 結論
リクエストに `validateOnly`（bool、既定 false）を足します。
true の時は実行時と同じ検査だけを行い、失敗なら実行時と同じエラーを、成功なら「実行していたら返るレスポンス」を返します。
これで、危険なメソッドでも送る前に結果を確かめられます。

読むだけで安価なメソッドには要りません。
実行して試せばよいからです。
ただし SQL を受け取るような高価な読み取りメソッドでは、構文の検査のために付ける価値があります。

## 2. 困る場面
ドキュメントの権限表、手元の認証情報、送ろうとしているリクエストを何度確認しても、実際に送るまで通るかどうかは分かりません。
読むだけのメソッドなら送って試せばよいのですが、作成、更新、削除は試すこと自体が本番のデータを変えます。
インフラ側で IAM ポリシーを組んで「この操作は通るのか」を試す時にも同じ悩みがあるので、この章の動機はすぐに腑に落ちました。
4-2 で、権限と形式を確かめたいだけのリクエストが本番に ChatRoom を 1 つ作ってしまうところを見ます。

## 3. 足すもの
増えるのはリクエストのフィールド 1 つと、検査を実行と共有する関数です。

`CreateChatRoomRequest` に `validateOnly` を足します。
省略時は false で普通のリクエストとして動き、true なら検証だけを行います。
既定を true にすると全リクエストが実行されなくなり、毎回フラグを付けて回ることになるので、既定は false 以外にありません。

検査の範囲は「実行時に返すエラーは検証時にも返す」です。
権限（403 Forbidden）、構文（400 Bad Request）、既存データとの衝突（409 Conflict）、参照先の存在を、どれも実行時と同じ条件で見ます。
アクセス制御サービスのような内部コンポーネントへの問い合わせも、データを変えない範囲なら行います。

成功した時は、実行時と同じ型で返します。
サーバーが採番する id のように埋められないフィールドは、空か、それらしい値にします。
利用者はこのレスポンスの全フィールドを当てにしない、という約束です。

書籍 27.3 が丁寧なのは、きれいに検証できない場合の扱いでした。
メール送信のように相手が検証モードを持たない外部依存は、その部分の検証を飛ばし、代わりに `@` の有無のような形式の検査だけをします。
抽選のように結果がランダムなメソッドでは、当たりでも外れでも本物として通用する値を返せばよく、確率を再現する必要はありません。
どちらも「副作用を出してまで検証しない」が優先です。

Go の型にするとこうなります。

```go
type CreateChatRoomRequest struct {
	Resource     ChatRoom `json:"resource"`
	ValidateOnly bool     `json:"validateOnly,omitempty"` // ①
}

// validate は実行時と同じ順・同じ条件で検査し、データは一切変えない。
func validate(s *store, token string, in CreateChatRoomRequest) (int, string) { // ②
	if token != "admin-token" {
		return http.StatusForbidden, "forbidden"
	}
	if in.Resource.Title == "" {
		return http.StatusBadRequest, "title is required"
	}
	if s.titleExists(in.Resource.Title) {
		return http.StatusConflict, errConflict.Error()
	}
	return 0, ""
}
```

- ① JSON に無ければ `false` です。bool の既定値がそのまま「普通のリクエスト」になります
- ② 戻り値はステータスコードとメッセージで、0 なら通ったことにします。検証と実行の両方がこの関数を呼びます

## 4. 前後比較
### 4-1. 使わない場合
検査をハンドラの中に順に書き、通ったら作る形です。

```go
func main() {
	s := &store{rooms: map[string]ChatRoom{}}
	mux := http.NewServeMux()

	mux.HandleFunc("POST /chatRooms", func(w http.ResponseWriter, req *http.Request) {
		token := strings.TrimPrefix(req.Header.Get("Authorization"), "Bearer ")
		if token != "admin-token" { // ① 権限
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		var in CreateChatRoomRequest
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		if in.Resource.Title == "" { // ② 構文
			http.Error(w, "title is required", http.StatusBadRequest)
			return
		}
		room, err := s.create(in.Resource) // ③ 既存データとの衝突
		if errors.Is(err, errConflict) {
			http.Error(w, err.Error(), http.StatusConflict)
			return
		}
		writeJSON(w, http.StatusOK, room)
	})

	log.Fatal(http.ListenAndServe(":8027", mux))
}
```

- ① ② ③ 検査が 3 か所に分かれていて、③ は作成と同じ関数の中にあります。「通るか」だけを知る入口がありません

:::message
`s.create` は同じ `title` が既にあれば `errConflict` を返します。
`errors.Is(err, errConflict)` は、`fmt.Errorf` の `%w` で包まれていても元のエラーかどうかを判定できます。
:::

### 4-2. 動かすと確かめただけの部屋が本番にできる
権限と形式が通るかを確かめる目的で、3 本送ります。

```
$ curl -s -i -X POST localhost:8027/chatRooms \
    -d '{"resource":{"title":"Chat about A"}}'
HTTP/1.1 403 Forbidden
Content-Type: text/plain; charset=utf-8

forbidden

$ curl -s -i -X POST localhost:8027/chatRooms \
    -H 'Authorization: Bearer admin-token' \
    -d '{"resource":{"title":""}}'
HTTP/1.1 400 Bad Request
Content-Type: text/plain; charset=utf-8

title is required

$ curl -s -i -X POST localhost:8027/chatRooms \
    -H 'Authorization: Bearer admin-token' \
    -d '{"resource":{"title":"Chat about A"}}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","title":"Chat about A"}

$ curl -s localhost:8027/chatRooms
{"results":[{"id":"1","title":"Chat about A"}]}
```

3 本目で「通る」と分かった時には、本番に `id: 1` ができています。
確かめたかっただけでも、消すには delete を別に送るしかありません。
delete のような破壊的なメソッドなら、試すこと自体ができないことになります。

### 4-3. 使う場合（差分）
検査を `validate` に集め、ハンドラは「検査、フラグを見る、実行」の順にします。
`store` には読むだけの `titleExists` を足しました。
リクエストの型と検査関数は丸ごと増える側です。

```diff go
 type CreateChatRoomRequest struct {
-	Resource ChatRoom `json:"resource"`
+	Resource     ChatRoom `json:"resource"`
+	ValidateOnly bool     `json:"validateOnly,omitempty"`
 }
+
+func (s *store) titleExists(title string) bool { // ①
+	s.mu.Lock()
+	defer s.mu.Unlock()
+	for _, x := range s.rooms {
+		if x.Title == title {
+			return true
+		}
+	}
+	return false
+}
+
+func validate(s *store, token string, in CreateChatRoomRequest) (int, string) {
+	if token != "admin-token" {
+		return http.StatusForbidden, "forbidden"
+	}
+	if in.Resource.Title == "" {
+		return http.StatusBadRequest, "title is required"
+	}
+	if s.titleExists(in.Resource.Title) {
+		return http.StatusConflict, errConflict.Error()
+	}
+	return 0, ""
+}
```

ハンドラは 3 か所にあった検査が 1 行になり、フラグの分岐が入ります。

```diff go
 	mux.HandleFunc("POST /chatRooms", func(w http.ResponseWriter, req *http.Request) {
 		token := strings.TrimPrefix(req.Header.Get("Authorization"), "Bearer ")
-		if token != "admin-token" {
-			http.Error(w, "forbidden", http.StatusForbidden)
-			return
-		}
 		var in CreateChatRoomRequest
 		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
 			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
 			return
 		}
-		if in.Resource.Title == "" {
-			http.Error(w, "title is required", http.StatusBadRequest)
+		if status, msg := validate(s, token, in); status != 0 { // ②
+			http.Error(w, msg, status)
 			return
 		}
-		room, err := s.create(in.Resource)
+		if in.ValidateOnly { // ③
+			writeJSON(w, http.StatusOK, ChatRoom{Title: in.Resource.Title})
+			return
+		}
+		room, err := s.create(in.Resource) // ④
 		if errors.Is(err, errConflict) {
 			http.Error(w, err.Error(), http.StatusConflict)
 			return
 		}
 		writeJSON(w, http.StatusOK, room)
 	})
```

- ① 4-1 で作成の中にあった衝突の検査を、読むだけの関数に分けて `validate` から呼びます
- ② 検証だけでも本番でも、同じ関数が同じエラーを返します
- ③ ここで `return` するので、保存場所には触りません
- ④ `validate` から `create` までの間に別のリクエストが同じ `title` を作ることがあるので、作成側の検査も残します

:::message
Go の関数は値を複数返せるので、`validate` は `(int, string)` を返しています。
`if status, msg := validate(...); status != 0 {` は、その場で 2 つを受け取ってから条件を見る書き方です。
:::

:::details after/main.go の全文
```go
package main

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
)

type ChatRoom struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

type CreateChatRoomRequest struct {
	Resource     ChatRoom `json:"resource"`
	ValidateOnly bool     `json:"validateOnly,omitempty"`
}

var errConflict = errors.New("title already exists")

type store struct {
	mu    sync.Mutex
	seq   int
	rooms map[string]ChatRoom
}

func (s *store) titleExists(title string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, x := range s.rooms {
		if x.Title == title {
			return true
		}
	}
	return false
}

func (s *store) create(r ChatRoom) (ChatRoom, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, x := range s.rooms {
		if x.Title == r.Title {
			return ChatRoom{}, errConflict
		}
	}
	s.seq++
	r.ID = strconv.Itoa(s.seq)
	s.rooms[r.ID] = r
	return r, nil
}

func (s *store) list() []ChatRoom {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []ChatRoom{}
	for i := 1; i <= s.seq; i++ {
		out = append(out, s.rooms[strconv.Itoa(i)])
	}
	return out
}

// validate は実行時と同じ順・同じ条件で検査し、データは一切変えない。
func validate(s *store, token string, in CreateChatRoomRequest) (int, string) {
	if token != "admin-token" {
		return http.StatusForbidden, "forbidden"
	}
	if in.Resource.Title == "" {
		return http.StatusBadRequest, "title is required"
	}
	if s.titleExists(in.Resource.Title) {
		return http.StatusConflict, errConflict.Error()
	}
	return 0, ""
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func main() {
	s := &store{rooms: map[string]ChatRoom{}}
	mux := http.NewServeMux()

	mux.HandleFunc("POST /chatRooms", func(w http.ResponseWriter, req *http.Request) {
		token := strings.TrimPrefix(req.Header.Get("Authorization"), "Bearer ")
		var in CreateChatRoomRequest
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		if status, msg := validate(s, token, in); status != 0 {
			http.Error(w, msg, status)
			return
		}
		if in.ValidateOnly {
			writeJSON(w, http.StatusOK, ChatRoom{Title: in.Resource.Title})
			return
		}
		room, err := s.create(in.Resource)
		if errors.Is(err, errConflict) {
			http.Error(w, err.Error(), http.StatusConflict)
			return
		}
		writeJSON(w, http.StatusOK, room)
	})
	mux.HandleFunc("GET /chatRooms", func(w http.ResponseWriter, req *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{"results": s.list()})
	})

	log.Fatal(http.ListenAndServe(":8127", mux))
}
```
:::

### 4-4. 同じ手順で動かすと本番に何も残らない
4-2 と同じ 3 本に `validateOnly: true` を付けて送ります。

```
$ curl -s -i -X POST localhost:8127/chatRooms \
    -d '{"validateOnly":true,"resource":{"title":"Chat about A"}}'
HTTP/1.1 403 Forbidden
Content-Type: text/plain; charset=utf-8

forbidden

$ curl -s -i -X POST localhost:8127/chatRooms \
    -H 'Authorization: Bearer admin-token' \
    -d '{"validateOnly":true,"resource":{"title":""}}'
HTTP/1.1 400 Bad Request
Content-Type: text/plain; charset=utf-8

title is required

$ curl -s -i -X POST localhost:8127/chatRooms \
    -H 'Authorization: Bearer admin-token' \
    -d '{"validateOnly":true,"resource":{"title":"Chat about A"}}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"","title":"Chat about A"}

$ curl -s localhost:8127/chatRooms
{"results":[]}
```

403 と 400 は 4-2 と同じです。
3 本目は 200 で `id` が空のレスポンスが返り、一覧は空のままでした。

```
$ curl -s -i -X POST localhost:8127/chatRooms \
    -H 'Authorization: Bearer admin-token' \
    -d '{"resource":{"title":"Chat about A"}}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","title":"Chat about A"}

$ curl -s -i -X POST localhost:8127/chatRooms \
    -H 'Authorization: Bearer admin-token' \
    -d '{"validateOnly":true,"resource":{"title":"Chat about A"}}'
HTTP/1.1 409 Conflict
Content-Type: text/plain; charset=utf-8

title already exists

$ curl -s localhost:8127/chatRooms
{"results":[{"id":"1","title":"Chat about A"}]}
```

本当に作った後に同じ本文を `validateOnly: true` で送ると、409 Conflict になります。
検証は、その時点の保存場所に対して行われています。

## 5. 1 リクエストの流れ
本番で検証のリクエストがサーバーの中をどう通るかを、順に追います。
送る側を利用者、受ける側をサーバー、`map` を保存場所と呼びます。

1. 利用者が `POST /chatRooms` に `{"validateOnly": true, "resource": {...}}` と `Authorization` ヘッダーを送る
2. サーバーは JSON を `CreateChatRoomRequest` に入れる。読めなければ 400
3. `validate` が実行時と同じ順で検査する。トークンが違えば 403、`title` が空なら 400、同じ `title` が保存場所にあれば 409。どれかに当たればそのエラーを返して終わる
4. `validateOnly` が true なら、保存場所を変えずに `ChatRoom{Title: ...}`（id は空）を 200 で返す
5. false なら作成して、採番した id 付きで 200 で返す
6. 利用者は 4 の結果を見てから、同じ本文から `validateOnly` を外して送る

## 6. 疑問と答え
読みながら引っかかったところです。

**なぜ別メソッドではなくフラグなのか**
フラグなら本文が実行時と完全に同じで、検証した内容をそのまま実行に回せます。
別メソッドだと、本文の形やパスがずれる余地が生まれます。

**検証だけなら権限の確認は省いてよいか**
省けません。
実行時に 403 になるなら検証でも 403 を返します。
利用者が一番間違えるのが権限の確認なので、ここを省くと検証の意味がなくなります。

**外部サービスにも問い合わせるのか**
データを変えない問い合わせ（アクセス制御、参照先の存在確認）はします。
相手に副作用が出る操作（テストメールの送信）はしません。
相手が検証モードを持っているなら、それを使います。

**レスポンスの id が空なのは手抜きではないか**
サーバーが採番する値は、実行しないと決まりません。
検証の目的は「通るか」の確認で、全フィールドの再現ではありません。

**読むだけのメソッドに `validateOnly` は無意味か**
安価なら無意味です。
大きなデータウェアハウスへの SQL のように高価なら、構文の検証だけ先にできる価値があります。
書籍 27.3 がこの例を挙げています。

**既定値を true にした方が安全ではないか**
全リクエストが実行されなくなり、毎回フラグを付けることになります。
既定は false にします。

ここまでを自分の言葉でまとめると、`validateOnly: true` は実行時と同じ検査を通して結果だけ見せ、保存場所は一切触らない、です。

## 7. トレードオフ
得られるのは、危険なメソッドでも事前に結果を確かめられることです。
高価なメソッドでは、利用者が「検証だけしたい」と表明できるので、無駄な実行も減ります。
引き換えに、検査と実行を分けて書く手間がかかり、外部依存やランダムな結果のように検証時に再現できない部分が残ります。

書籍 27.4 は、必須になることはほとんどないが利用者にとっては便利な機能だ、と位置付けています。
対応するメソッドとしないメソッドがあってよいので、副作用が大きいメソッドから付けるのが現実的だと私は読みました。

## 8. 参考
- 『APIデザイン・パターン』JJ Geewax 著、マイナビ出版、第 27 章
- https://google.aip.dev/163
- AWS EC2 の多くの操作（`RunInstances` など）は `DryRun` パラメータを持ち、権限があるかを実行せずに確かめます。権限があれば `DryRunOperation`、無ければ `UnauthorizedOperation` のエラーが返るので、成功もエラーで知らせる点がこのパターンと違います: https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_RunInstances.html
