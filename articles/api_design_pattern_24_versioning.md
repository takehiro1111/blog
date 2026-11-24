---
title: "[Go]APIデザインパターン 24: バージョン管理と互換性（使う/使わないの前後比較）"
emoji: "📘"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Go", "API", "設計", "デザインパターン"]
published: false
---
![](/images/go/go_logo.png =450x)

## 本記事の内容
- 『APIデザイン・パターン』(JJ Geewax 著、マイナビ出版) の第 24 章「バージョン管理と互換性」を、Go で書き直しながら読んだメモです
- バージョンを切らずにフィールドを改名した実装と、`/v1` と `/v2` を並行して出す実装を同じ手順で動かして、何が変わるかを出力で確かめます
- コードは Go 1.22 以降の `net/http` と標準ライブラリだけで動きます
- シリーズの目次は「[Go]APIデザインパターン 00: 目次と、パターンを使わないとどうなるか」にあります

## 1. 結論
公開済みのリクエストとレスポンスの形は変えません。
既存のコードが動かなくなる変更（フィールドの改名など）は、`/v2` のような別のバージョンとして並行して提供します。
こうしておくと、利用者は自分の都合で v2 に移る時期を決められます。

利用者が自分のチームだけで、全員が同時にコードを直せる内部 API なら、バージョンを切らずに直接変える方が安く済みます。

## 2. 困る場面
利用者は、使い始めた時の API の形が変わらない前提でコードを書きます。
一方で API を作る側は、機能追加やバグ修正、法律への対応で変えざるを得ません。
Web API には利用者の手元にコピーが無いので、サーバー側の変更はそのまま全利用者に届きます。

この章を読んでいて最初に引っかかったのは、壊れた時にエラーが出るとは限らない、という点でした。
4-2 で、`title` を `name` に改名しただけのサーバーに改名前のリクエストを送るとどうなるかを見ます。

## 3. 足すもの
増えるのは、URL のバージョン識別子（`/v1`、`/v2`）と、何を後方互換とみなすかの方針、それに古いバージョンをいつ止めるかの非推奨ポリシーです。
実装で済むのは 1 つ目だけで、残りの 2 つは利用者を見て決める部分になります。

判断軸は「前のバージョン向けに書かれたコードが動かなくなるか」ですが、書籍 24.2.2 は判断が分かれる変更を並べています。
私が読んで意外だったものを挙げます。

- フィールドの追加は多くの API で互換扱いですが、全件取得して全部をメモリに載せる IoT 機器のような利用者がいると、レスポンスが増えただけで落ちます
- 500 Internal Server Error を直すのは互換です。「間違っているのに 200 OK で成功していた」動作を 400 Bad Request に直すと、その動作に頼っていた利用者が壊れます
- 浮動小数点の誤差を直して結果の数値が変わるのも、利用者によっては非互換です
- 応答時間が 100 ミリ秒から 10 秒になる、機械学習モデルを入れ替えて結果が変わる、といったインターフェースに現れない変更も同じ扱いです
- 送信頻度の制限を後から入れると、連続送信していたコードが止まります。エラーにするか遅延させるかで、壊れ方も変わります

バージョンの切り方は 3 つ紹介されています。

- 永久安定方式は、v1 には互換の変更だけを入れ、非互換の変更は v2 に溜めてから出します。v1 は原則ずっと動かします。Google Cloud の多くの API がこの方式です
- アジャイルインスタビリティは、各バージョンが「プレビュー、現行、非推奨、削除」を順に進む方式です。現行とプレビューは常に 1 つずつで、古いバージョン向けのコードは宣言した期限で必ず止まります
- セマンティックバージョン管理（SemVer）は、メジャー（非互換）、マイナー（互換の機能追加）、パッチ（互換のバグ修正）の 3 つの数字で変更の意味を伝えます。利用者は細かく固定できますが、稼働させるバージョン数が増えます

この記事の実装は永久安定方式で、パスにバージョンを置きます。
Go の型では、保存する形と公開する形を分けるところがポイントです。

```go
type ChatRoom struct { // ① 保存する形。公開する形とは分ける
	ID   string
	Name string
}

type ChatRoomV1 struct { // ② 公開済みの形。もう変えない
	ID    string `json:"id"`
	Title string `json:"title"`
}

type ChatRoomV2 struct { // ③ 互換性のない変更（title → name）はこちらだけ
	ID   string `json:"id"`
	Name string `json:"name"`
}

func toV1(r ChatRoom) ChatRoomV1 { return ChatRoomV1{ID: r.ID, Title: r.Name} }
func toV2(r ChatRoom) ChatRoomV2 { return ChatRoomV2{ID: r.ID, Name: r.Name} }
```

- ① json タグを付けません。この型は保存場所との間でしか使いません
- ② ③ 公開する形はバージョンごとに別の型にして、変換関数で保存する形と行き来します

## 4. 前後比較
### 4-1. 使わない場合
バージョンの概念が無く、`/chatRooms` が 1 つだけある形です。

```go
type ChatRoom struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

type CreateChatRoomRequest struct {
	Resource ChatRoom `json:"resource"`
}

func main() {
	s := &store{rooms: map[string]ChatRoom{}}
	mux := http.NewServeMux()

	mux.HandleFunc("POST /chatRooms", func(w http.ResponseWriter, req *http.Request) {
		var in CreateChatRoomRequest
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, http.StatusOK, s.create(in.Resource))
	})

	mux.HandleFunc("GET /chatRooms/{id}", func(w http.ResponseWriter, req *http.Request) {
		room, ok := s.get(req.PathValue("id"))
		if !ok {
			http.Error(w, "not found", http.StatusNotFound)
			return
		}
		writeJSON(w, http.StatusOK, room)
	})

	log.Fatal(http.ListenAndServe(":8024", mux))
}
```

これを公開した後で `title` を `name` に改名し、同じ URL にデプロイします。
変えるのは struct の 1 行だけです。

```diff go
 type ChatRoom struct {
-	ID    string `json:"id"`
-	Title string `json:"title"`
+	ID   string `json:"id"`
+	Name string `json:"name"`
 }
```

### 4-2. 動かすと 200 OK のまま中身が消える
改名前に動いていた利用者のリクエストを、改名前と改名後のサーバーに送ります。

```
# 改名前
$ curl -s -i -X POST localhost:8024/chatRooms \
    -d '{"resource":{"title":"Chat about A"}}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","title":"Chat about A"}

# 改名後。利用者のコードは変えていない
$ curl -s -i -X POST localhost:8224/chatRooms \
    -d '{"resource":{"title":"Chat about A"}}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","name":""}

$ curl -s localhost:8224/chatRooms/1
{"id":"1","name":""}
```

改名後も 200 OK が返りますが、`name` は空で保存され、レスポンスに `title` はありません。
利用者のコードは `title` を読んで空文字を受け取ります。
ステータスが 200 なので、監視でも気付けないのが怖いところです。

:::message
Go の `encoding/json` は、struct に無いキー（ここでは `title`）を既定では黙って捨てます。
`dec.DisallowUnknownFields()` を呼べば未知のキーを 400 にできますが、それでも古い利用者が壊れることに変わりはありません。
:::

### 4-3. 使う場合（差分）
保存する形は 1 つのまま、公開する形を v1 と v2 に分けます。
`store` は 4-1 と同じで、保存する型から json タグが無くなっただけです。
ハンドラの差分はこうなります。

```diff go
-	mux.HandleFunc("POST /chatRooms", func(w http.ResponseWriter, req *http.Request) {
-		var in CreateChatRoomRequest
+	mux.HandleFunc("POST /v1/chatRooms", func(w http.ResponseWriter, req *http.Request) {
+		var in struct {
+			Resource ChatRoomV1 `json:"resource"`
+		}
 		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
 			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
 			return
 		}
-		writeJSON(w, http.StatusOK, s.create(in.Resource))
+		writeJSON(w, http.StatusOK, toV1(s.create(ChatRoom{Name: in.Resource.Title}))) // ①
 	})
-
-	mux.HandleFunc("GET /chatRooms/{id}", func(w http.ResponseWriter, req *http.Request) {
+	mux.HandleFunc("GET /v1/chatRooms/{id}", func(w http.ResponseWriter, req *http.Request) {
 		room, ok := s.get(req.PathValue("id"))
 		if !ok {
 			http.Error(w, "not found", http.StatusNotFound)
 			return
 		}
-		writeJSON(w, http.StatusOK, room)
+		writeJSON(w, http.StatusOK, toV1(room))
 	})
 
-	log.Fatal(http.ListenAndServe(":8024", mux))
+	mux.HandleFunc("POST /v2/chatRooms", func(w http.ResponseWriter, req *http.Request) { // ②
+		var in struct {
+			Resource ChatRoomV2 `json:"resource"`
+		}
+		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
+			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
+			return
+		}
+		writeJSON(w, http.StatusOK, toV2(s.create(ChatRoom{Name: in.Resource.Name})))
+	})
+	mux.HandleFunc("GET /v2/chatRooms/{id}", func(w http.ResponseWriter, req *http.Request) {
+		room, ok := s.get(req.PathValue("id"))
+		if !ok {
+			http.Error(w, "not found", http.StatusNotFound)
+			return
+		}
+		writeJSON(w, http.StatusOK, toV2(room))
+	})
+
+	log.Fatal(http.ListenAndServe(":8124", mux))
 }
```

- ① v1 は `title` で受けて保存する形の `Name` に入れ、返す時も `title` に戻します
- ② 改名は v2 のハンドラにだけ入れます。v1 のハンドラには触りません

:::message
`var in struct{...}` は、このハンドラの中でだけ使う名前の無い struct です。
リクエストの形がバージョンごとに違うので、型をハンドラに閉じ込めています。
:::

:::details after/main.go の全文
```go
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"sync"
)

type ChatRoom struct { // ① 保存する形。公開する形とは分ける
	ID   string
	Name string
}

type ChatRoomV1 struct { // ② 公開済みの形。もう変えない
	ID    string `json:"id"`
	Title string `json:"title"`
}

type ChatRoomV2 struct { // ③ 互換性のない変更（title → name）はこちらだけ
	ID   string `json:"id"`
	Name string `json:"name"`
}

func toV1(r ChatRoom) ChatRoomV1 { return ChatRoomV1{ID: r.ID, Title: r.Name} }
func toV2(r ChatRoom) ChatRoomV2 { return ChatRoomV2{ID: r.ID, Name: r.Name} }

type store struct {
	mu    sync.Mutex
	seq   int
	rooms map[string]ChatRoom
}

func (s *store) create(r ChatRoom) ChatRoom {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.seq++
	r.ID = strconv.Itoa(s.seq)
	s.rooms[r.ID] = r
	return r
}

func (s *store) get(id string) (ChatRoom, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	r, ok := s.rooms[id]
	return r, ok
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func main() {
	s := &store{rooms: map[string]ChatRoom{}}
	mux := http.NewServeMux()

	mux.HandleFunc("POST /v1/chatRooms", func(w http.ResponseWriter, req *http.Request) {
		var in struct {
			Resource ChatRoomV1 `json:"resource"`
		}
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, http.StatusOK, toV1(s.create(ChatRoom{Name: in.Resource.Title})))
	})
	mux.HandleFunc("GET /v1/chatRooms/{id}", func(w http.ResponseWriter, req *http.Request) {
		room, ok := s.get(req.PathValue("id"))
		if !ok {
			http.Error(w, "not found", http.StatusNotFound)
			return
		}
		writeJSON(w, http.StatusOK, toV1(room))
	})

	mux.HandleFunc("POST /v2/chatRooms", func(w http.ResponseWriter, req *http.Request) {
		var in struct {
			Resource ChatRoomV2 `json:"resource"`
		}
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, http.StatusOK, toV2(s.create(ChatRoom{Name: in.Resource.Name})))
	})
	mux.HandleFunc("GET /v2/chatRooms/{id}", func(w http.ResponseWriter, req *http.Request) {
		room, ok := s.get(req.PathValue("id"))
		if !ok {
			http.Error(w, "not found", http.StatusNotFound)
			return
		}
		writeJSON(w, http.StatusOK, toV2(room))
	})

	log.Fatal(http.ListenAndServe(":8124", mux))
}
```
:::

### 4-4. 同じ手順で動かすと v1 の返事は 1 文字も変わらない
v1 の利用者は改名前と同じリクエストを `/v1` に送り、v2 の利用者は `/v2` に送ります。

```
$ curl -s -i -X POST localhost:8124/v1/chatRooms \
    -d '{"resource":{"title":"Chat about A"}}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","title":"Chat about A"}

$ curl -s -i -X POST localhost:8124/v2/chatRooms \
    -d '{"resource":{"name":"Chat about B"}}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"2","name":"Chat about B"}

$ curl -s localhost:8124/v1/chatRooms/2
{"id":"2","title":"Chat about B"}

$ curl -s localhost:8124/v2/chatRooms/1
{"id":"1","name":"Chat about A"}
```

v1 のレスポンスは改名前と同じです。
v2 で作った `id: 2` を v1 で読むと `title` で返ってくるので、保存データが共有されていることも分かります。

## 5. 1 リクエストの流れ
本番でリクエストがサーバーの中をどう通るかを、順に追います。
送る側を利用者、受ける側をサーバー、`ChatRoom` を保存する形、`ChatRoomV1` と `ChatRoomV2` を公開する形と呼びます。

1. 利用者が `POST /v1/chatRooms` に `{"resource":{"title":"Chat about A"}}` を送る
2. サーバーはパスの `/v1` でハンドラを選ぶ（`ServeMux` のパターン一致）
3. JSON を v1 の公開する形に入れる。読めなければ 400
4. 保存する形に変換して（`ChatRoom{Name: title}`）保存し、id を採番する
5. 保存した結果を v1 の公開する形に戻し、200 で返す
6. v2 の利用者が同じ部屋を `GET /v2/chatRooms/1` で読むと、同じ保存データが `name` で返る

保存する形を 1 つにしておくと、バージョンが増えても保存場所とデータ移行は増えません。

## 6. 疑問と答え
読みながら引っかかったところです。

**後方互換とは何か**
前のバージョン向けに書かれた利用者のコードが、新しいバージョンに切り替わっても期待どおりに動くことです。
API を作る側は利用者のコードを変えられないので、サーバー側の変更が既存のコードを壊さないかだけを見ます。

**フィールドを足すだけなら必ず互換と言ってよいか**
多くの API ではそう扱います。
ただし全件取得して全部をメモリに載せる IoT 機器のような利用者がいれば、レスポンスの増加で落ちます。
だから方針として先に決めておく必要があります。

**なぜ改名は v1 に入れてはいけないのに、バグ修正は入れてよいのか**
500 を返していた箇所を直しても、誰のコードも止まりません。
改名は `title` を読むコードを全部止めます。
判断軸は「動いていたコードが止まるか」であって、変更の大きさではありません。

**「間違った 200 OK」を 400 Bad Request に直すのは互換か**
その 200 に頼っているコードがあるなら非互換です。
利用者が安定を重視するなら v2 で直し、SemVer ならメジャーを上げます。
書籍 24.5 の練習問題 4 がこの論点です。

**古いバージョンはいつまで動かすのか**
永久安定方式なら原則ずっとです。
アジャイルインスタビリティなら、非推奨にしてから宣言した期間（例えば 2 か月）で削除します。
どちらでも、期間を先に公表して守ることが条件になります。

**v1 と v2 でデータは別になるのか**
同じです。
この記事の実装では保存する形は 1 つで、公開する形だけを v1 と v2 で変換しています。
だから v2 で作った部屋を v1 で読めます。

ここまでを自分の言葉でまとめると、既存のコードが止まる変更は別の URL（v2）に出して v1 は動かし続ける、何が「止まる変更」かは利用者の期待から決めて方針として先に書いておく、です。

## 7. トレードオフ
得られるのは、変更を続けながら既存の利用者を壊さないことです。
引き換えに、動かすバージョンの数だけ運用が増え、何を互換とみなすかの判断を毎回迫られます。

書籍 24.4 は、この判断を 3 つの軸で整理しています。
全変更を新バージョンにすると利用者は好きな時点に固定できますが、v100 まで増えて選べなくなります（細かさと単純さ）。
変えなければ互換の判断は要りませんが、OS やライブラリの更新すら利用者に見える形で漏れます（安定性と新機能）。
利用者は「使えない、不満、大丈夫、満足」に分かれ、満足を最大にすると使えない人が増え、使えない人を最小にすると不満な人が増えます（満足度と遍在度）。
どれも中間を狙うことになり、どこが中間かは利用者が銀行なのかスタートアップなのかで変わります。

## 8. 参考
- 『APIデザイン・パターン』JJ Geewax 著、マイナビ出版、第 24 章
- https://google.aip.dev/180 （後方互換性）、https://google.aip.dev/181 （安定性レベル）、https://google.aip.dev/185 （API のバージョン管理）
- https://semver.org/
- AWS EC2 の Query API は全リクエストに共通パラメータ `Version`（例: `Version=2016-11-15`）を持ち、どの日付版の API に向けて書いたリクエストかを指定します: https://docs.aws.amazon.com/AWSEC2/latest/APIReference/CommonParameters.html
