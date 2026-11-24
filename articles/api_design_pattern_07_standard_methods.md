---
title: "[Go]APIデザインパターン 7: 標準メソッド（使う/使わないの前後比較）"
emoji: "📘"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Go", "API", "設計", "デザインパターン"]
published: false
---
![](/images/go/go_logo.png =450x)

## 本記事の内容
- 『APIデザイン・パターン』(JJ Geewax 著、マイナビ出版) の第 7 章「標準メソッド」を、Go で書き直しながら読んだメモです
- やりたいことごとに名前を付けた RPC と、Get / List / Create / Update / Delete の標準メソッドを同じ手順で動かして、何が変わるかを出力で確かめます
- コードは Go 1.22 以降の `net/http` と標準ライブラリだけで動きます
- シリーズの目次は「[Go]APIデザインパターン 00: 目次と、パターンを使わないとどうなるか」にあります

## 1. 結論
リソースに対してできる操作を Get、List、Create、Update、Delete の 5 つに固定し、どのリソースでも同じ HTTP メソッド、同じパス、同じ返し方にします。
利用者は 5 つの動きを一度覚えれば、新しいリソースの名前を知るだけで、そのリソースの操作の仕方が分かります。

| 標準メソッド | HTTP | パス | 返すもの |
|---|---|---|---|
| Create | POST | `/chatRooms` | 作ったリソース |
| Get | GET | `/chatRooms/{id}` | リソース |
| List | GET | `/chatRooms` | `{"results": [...]}` |
| Update | PATCH | `/chatRooms/{id}` | 更新後のリソース |
| Delete | DELETE | `/chatRooms/{id}` | 空（204 No Content） |
| Replace | PUT | `/chatRooms/{id}` | 置き換え後のリソース |

Replace は書籍が準標準と呼んでいるもので、Update との違いは「6. 疑問と答え」に書きました。

## 2. 困る場面
最初に思いつくのは、やりたいことが増えるたびに `scheduleRoom`、`showRoomDetails`、`cancelRoom` のような名前のエンドポイントを足していく形です。
作っている間は困りません。
困るのは利用者が増えてからです。

- 作成の返事が `{"id":1}` だけなので、作ったものを見るためにもう 1 回呼ぶことになります
- `GET /rooms/1` のように推測した URL は 404 になり、リソースが無いのか URL が無いのか区別できません
- 取得するたびに閲覧数が増えるなど、読むだけのはずのメソッドが状態を変えます
- 無いものを削除しても `{"ok":true}` が返るので、2 回目の削除や打ち間違いに気付けません
- パラメータ名が `room` だったり `roomId` だったりして、1 つ覚えても次のメソッドで使えません

書籍の 7.1 節は、利用者が API について学ぶことが少ないほど早く使い始められる、という言い方でこの問題を説明しています。
4-2 で、上の 5 つが実際に起きるところを見ます。

## 3. 足すもの
足すというより、決め事をそろえます。
書籍が各メソッドに決めている細かい点を、自分の言葉で並べておきます。

Create は POST で、本文にリソースを入れて送り、返事は作られたリソースそのものです。
識別子はサーバーが決めます（第 6 章）。
作成の返事が返った時点で、その部屋は Get にも List にも必ず出てくる、という強い一貫性を書籍は求めています。
ストレージの都合で結果整合性にしかならないなら、標準の Create ではなくカスタムメソッドの Import（第 23 章）やロングランオペレーション（第 10 章）にします。

Get は識別子だけを受け取って、保存されているリソースをそのまま返します。
副作用を持たず、何度呼んでも同じ結果になります。

List はコレクションを対象にします。
`GET /chatRooms` には親がなく、`GET /chatRooms/{parent}/messages` のように親があるコレクションは親を指定します。
返すのは利用者がアクセスできるものだけで、人によって結果が違ってかまいません。
総件数とソートは、データが増えた時に重くなるので付けません。
絞り込みだけは `filter` という文字列で受けます（第 22 章）。

Update は PATCH で、指定されたフィールドだけを変えます。
「アーカイブ済みにする」のような状態の遷移は、Update ではなくカスタムメソッド（第 9 章）にします。
どのフィールドを変えるかの伝え方は、第 8 章で扱います。

Delete は DELETE で、成功したら本文を返しません。
対象が無ければ 404 Not Found です。
2 回続けて呼ぶと 2 回目は失敗するので、Delete はべき等ではありません。

どのリソースも、特別な理由がない限り 5 つ全部をサポートします。
サポートしないメソッドは 405 Method Not Allowed、そのリソース 1 件だけ許可しない操作は 403 Forbidden で返し、ルートを省略して 404 にすることは避けます。

Go では型が 2 つあれば足ります。

```go
type ChatRoom struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

type ListChatRoomsResponse struct { // ①
	Results []ChatRoom `json:"results"`
}
```

- ① List の返事はリソースの配列を直接返さず、`results` に入れます。後からページ分割（第 21 章）の `nextPageToken` を足せるようにするためです

:::message
Go 1.22 の `http.NewServeMux` は、`"GET /chatRooms/{id}"` のようにメソッドとパスをまとめて登録できます。
同じパスに別のメソッドで来たリクエストには、自動で 405 Method Not Allowed と `Allow` ヘッダーを返します。
`{id}` の部分は `req.PathValue("id")` で取れます。
:::

## 4. 前後比較
### 4-1. 使わない場合
やりたいことごとにエンドポイントを足した形です。
5 つあるうち、作成・取得・削除の 3 つを抜粋します。

```go
	mux.HandleFunc("POST /scheduleRoom", func(w http.ResponseWriter, req *http.Request) { // ①
		var in struct {
			Name string `json:"name"`
		}
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		s.mu.Lock()
		defer s.mu.Unlock()
		s.seq++
		s.rooms[s.seq] = &room{ID: s.seq, Name: in.Name}
		writeJSON(w, http.StatusOK, map[string]int{"id": s.seq}) // ②
	})

	mux.HandleFunc("GET /showRoomDetails", func(w http.ResponseWriter, req *http.Request) {
		id, _ := strconv.Atoi(req.URL.Query().Get("room"))
		s.mu.Lock()
		defer s.mu.Unlock()
		r, ok := s.rooms[id]
		if !ok {
			http.Error(w, "not found", http.StatusNotFound)
			return
		}
		r.Views++ // ③
		writeJSON(w, http.StatusOK, r)
	})

	mux.HandleFunc("POST /cancelRoom", func(w http.ResponseWriter, req *http.Request) {
		var in struct {
			RoomID int `json:"roomId"`
		}
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		s.mu.Lock()
		delete(s.rooms, in.RoomID)
		s.mu.Unlock()
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true}) // ④
	})
```

- ① 動詞から名前を決めています。別の人が足した `renameRoom` や `showAllRooms` も同じ調子です
- ② 作った部屋ではなく、番号だけ返します
- ③ 取得のたびに閲覧数を増やしています。読むだけのつもりのリクエストで状態が変わります
- ④ 対象が無くても `delete` は何も言わないので、常に `ok` です

### 4-2. 動かすと作ったものが見えず、読むだけで数字が増え、消えていても ok が返る
```
$ curl -s -i -X POST localhost:8007/scheduleRoom -d '{"name":"Room A"}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":1}

$ curl -s -i localhost:8007/rooms/1
HTTP/1.1 404 Not Found
Content-Type: text/plain; charset=utf-8

404 page not found

$ curl -s -i 'localhost:8007/showRoomDetails?room=1'
HTTP/1.1 200 OK
Content-Type: application/json

{"roomId":1,"name":"Room A","views":1}

$ curl -s -i 'localhost:8007/showRoomDetails?room=1'
HTTP/1.1 200 OK
Content-Type: application/json

{"roomId":1,"name":"Room A","views":2}
```

作成の返事には部屋の中身がなく、URL を推測すると 404 で、同じ GET を 2 回すると `views` が変わります。
削除は 2 回とも成功します。

```
$ curl -s -i -X POST localhost:8007/cancelRoom -d '{"roomId":1}'
HTTP/1.1 200 OK
Content-Type: application/json

{"ok":true}

$ curl -s -i -X POST localhost:8007/cancelRoom -d '{"roomId":1}'
HTTP/1.1 200 OK
Content-Type: application/json

{"ok":true}
```

### 4-3. 使う場合（差分）
エンドポイントを標準メソッドに置き換えます。
作成・取得・削除の 3 つを差分で見ます。

```diff go
-	mux.HandleFunc("POST /scheduleRoom", func(w http.ResponseWriter, req *http.Request) {
-		var in struct {
-			Name string `json:"name"`
-		}
-		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
+	mux.HandleFunc("POST /chatRooms", func(w http.ResponseWriter, req *http.Request) {
+		var room ChatRoom
+		if err := json.NewDecoder(req.Body).Decode(&room); err != nil {
 			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
 			return
 		}
 		s.mu.Lock()
 		defer s.mu.Unlock()
 		s.seq++
-		s.rooms[s.seq] = &room{ID: s.seq, Name: in.Name}
-		writeJSON(w, http.StatusOK, map[string]int{"id": s.seq})
+		room.ID = strconv.Itoa(s.seq)
+		s.rooms[room.ID] = room
+		writeJSON(w, http.StatusOK, room) // ①
 	})

-	mux.HandleFunc("GET /showRoomDetails", func(w http.ResponseWriter, req *http.Request) {
-		id, _ := strconv.Atoi(req.URL.Query().Get("room"))
+	mux.HandleFunc("GET /chatRooms/{id}", func(w http.ResponseWriter, req *http.Request) { // ②
 		s.mu.Lock()
-		defer s.mu.Unlock()
-		r, ok := s.rooms[id]
+		room, ok := s.rooms[req.PathValue("id")]
+		s.mu.Unlock()
 		if !ok {
 			http.Error(w, "not found", http.StatusNotFound)
 			return
 		}
-		r.Views++
-		writeJSON(w, http.StatusOK, r)
+		writeJSON(w, http.StatusOK, room)
 	})

+	mux.HandleFunc("GET /chatRooms", func(w http.ResponseWriter, req *http.Request) { // ③
+		writeJSON(w, http.StatusOK, ListChatRoomsResponse{Results: s.list()})
+	})
+
-	mux.HandleFunc("POST /cancelRoom", func(w http.ResponseWriter, req *http.Request) {
-		var in struct {
-			RoomID int `json:"roomId"`
-		}
-		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
-			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
-			return
-		}
+	mux.HandleFunc("DELETE /chatRooms/{id}", func(w http.ResponseWriter, req *http.Request) {
 		s.mu.Lock()
-		delete(s.rooms, in.RoomID)
-		s.mu.Unlock()
-		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
+		defer s.mu.Unlock()
+		id := req.PathValue("id")
+		if _, ok := s.rooms[id]; !ok { // ④
+			http.Error(w, "not found", http.StatusNotFound)
+			return
+		}
+		delete(s.rooms, id)
+		w.WriteHeader(http.StatusNoContent) // ⑤
 	})
```

- ① 作った部屋そのものを返します
- ② 識別子はクエリではなくパスで受け取り、閲覧数のような余計な更新はしません
- ③ 一覧は `results` に入れて返します
- ④ 無いものを消そうとしたら 404 です
- ⑤ 成功時は本文なしの 204 No Content です

Update は `PATCH /chatRooms/{id}` で、この章では本文の `title` があればそれだけ書き換える形にしてあります。
省略したフィールドとゼロ値の区別がこの形では付かないので、きちんとした部分更新は第 8 章で書き直します。

:::message
`w.WriteHeader(http.StatusNoContent)` だけを呼ぶと、本文なしで 204 が返ります。
`http.Error` は本文と `Content-Type: text/plain` を付けてしまうので、204 には使いません。
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

type ChatRoom struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

type ListChatRoomsResponse struct {
	Results []ChatRoom `json:"results"`
}

type store struct {
	mu    sync.Mutex
	seq   int
	rooms map[string]ChatRoom
}

func (s *store) list() []ChatRoom {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []ChatRoom{}
	for i := 1; i <= s.seq; i++ {
		if r, ok := s.rooms[strconv.Itoa(i)]; ok {
			out = append(out, r)
		}
	}
	return out
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func main() {
	s := &store{rooms: map[string]ChatRoom{}}
	mux := http.NewServeMux()

	mux.HandleFunc("POST /chatRooms", func(w http.ResponseWriter, req *http.Request) { // ①
		var room ChatRoom
		if err := json.NewDecoder(req.Body).Decode(&room); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		s.mu.Lock()
		defer s.mu.Unlock()
		s.seq++
		room.ID = strconv.Itoa(s.seq)
		s.rooms[room.ID] = room
		writeJSON(w, http.StatusOK, room)
	})

	mux.HandleFunc("GET /chatRooms/{id}", func(w http.ResponseWriter, req *http.Request) { // ②
		s.mu.Lock()
		room, ok := s.rooms[req.PathValue("id")]
		s.mu.Unlock()
		if !ok {
			http.Error(w, "not found", http.StatusNotFound)
			return
		}
		writeJSON(w, http.StatusOK, room)
	})

	mux.HandleFunc("GET /chatRooms", func(w http.ResponseWriter, req *http.Request) { // ③
		writeJSON(w, http.StatusOK, ListChatRoomsResponse{Results: s.list()})
	})

	mux.HandleFunc("PATCH /chatRooms/{id}", func(w http.ResponseWriter, req *http.Request) { // ④
		var in ChatRoom
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		s.mu.Lock()
		defer s.mu.Unlock()
		room, ok := s.rooms[req.PathValue("id")]
		if !ok {
			http.Error(w, "not found", http.StatusNotFound)
			return
		}
		if in.Title != "" {
			room.Title = in.Title
		}
		s.rooms[room.ID] = room
		writeJSON(w, http.StatusOK, room)
	})

	mux.HandleFunc("DELETE /chatRooms/{id}", func(w http.ResponseWriter, req *http.Request) { // ⑤
		s.mu.Lock()
		defer s.mu.Unlock()
		id := req.PathValue("id")
		if _, ok := s.rooms[id]; !ok {
			http.Error(w, "not found", http.StatusNotFound)
			return
		}
		delete(s.rooms, id)
		w.WriteHeader(http.StatusNoContent)
	})

	log.Fatal(http.ListenAndServe(":8107", mux))
}
```
:::

### 4-4. 同じ手順で動かすと作ったものが返り、読んでも変わらず、2 回目の削除は 404
```
$ curl -s -i -X POST localhost:8107/chatRooms -d '{"title":"Room A"}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","title":"Room A"}

$ curl -s -i localhost:8107/chatRooms/1
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","title":"Room A"}

$ curl -s -i localhost:8107/chatRooms/1
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","title":"Room A"}

$ curl -s -i localhost:8107/chatRooms
HTTP/1.1 200 OK
Content-Type: application/json

{"results":[{"id":"1","title":"Room A"}]}
```

作成の返事がそのまま部屋で、Get は 2 回呼んでも同じです。
用意していないメソッドで呼ぶと 405 になり、`Allow` ヘッダーで使えるメソッドが分かります。
削除は 2 回目が 404 です。

```
$ curl -s -i -X POST localhost:8107/chatRooms/1 -d '{}'
HTTP/1.1 405 Method Not Allowed
Allow: DELETE, GET, HEAD, PATCH
Content-Type: text/plain; charset=utf-8

Method Not Allowed

$ curl -s -i -X DELETE localhost:8107/chatRooms/1
HTTP/1.1 204 No Content

$ curl -s -i -X DELETE localhost:8107/chatRooms/1
HTTP/1.1 404 Not Found
Content-Type: text/plain; charset=utf-8

not found
```

## 5. 1 リクエストの流れ
Create が返ってから Delete が返るまでを、サーバーの中の順で追います。

1. 利用者が `POST /chatRooms` に部屋の JSON を送る
2. サーバーは本文を `ChatRoom` に入れる。読めなければ 400
3. `Mutex` を取り、連番から識別子を決めて `map` に入れる
4. 保存した部屋を 200 で返す。この時点から `GET /chatRooms/1` と `GET /chatRooms` の両方に同じ部屋が出る
5. 利用者が `DELETE /chatRooms/1` を送る
6. サーバーは `map` に `1` があるか見る。無ければ 404
7. あれば消して、本文なしの 204 を返す
8. もう一度同じ DELETE が来ると、6 で 404 になる

## 6. 疑問と答え
読みながら引っかかったところです。

**Delete がべき等ではない、というのは直感に反する**
私も最初は「消えていれば目的は達しているので成功でいい」と思いました。
書籍は、リソース指向の API は「消せ」という命令を受け取る命令型なので、対象が無ければ失敗、と整理しています。
Kubernetes のように「無い状態にせよ」と宣言する API なら 2 回目も成功でよく、どちらの型の API かで答えが変わります。

**Delete が 404 を返すなら、再試行が怖くないか**
レスポンスが届かなかっただけで 2 回目が 404 になる、という状況は確かに起きます。
その問題は第 26 章の `requestId` で扱っていて、この章では「失敗する」とだけ決めています。

**閲覧数カウンターくらいの副作用も駄目なのか**
書籍の答えは「場合による」です。
カウンターの更新で遅くなるか、更新に失敗した時に取得まで失敗させるのか、が判断の材料になります。
メール送信や外部サービスへの接続のように目に見える副作用は、標準メソッドには入れません。

**List に総件数やソートを付けないのはなぜか**
データが少ないうちは簡単でも、複数のストレージに分散した後に正確な件数や全体の並び順を出すのは重い処理になるからです。
どうしても件数が要るなら、後で推定値に変えられるように `resultCountEstimate` のような名前にしておく、というのが書籍の勧めです。

**Update と Replace は何が違うのか**
Update は PATCH で指定したフィールドだけを変え、Replace は PUT で本文のとおりにリソース全体を置き換えます。
Replace は利用者が知らないフィールドも消すので、「全部こうしたい」が明確な時だけ使います。
Replace で存在しないリソースを作ることもできますが、Create の代わりにはしません。

**あるリソースで Update を使わせたくない時、ルートを消していいのか**
消さずに 405 を返します。
ルートを消すと 404 になり、利用者にはリソースが無いように見えてしまいます。
そのリソース 1 件だけ変更禁止なら 403 Forbidden です。

ここまでを自分の言葉でまとめると、操作の名前を考えるのをやめて 5 つのメソッドに乗せ、返すもの・ステータス・べき等性までそろえることで、利用者が覚えることを減らす、です。

## 7. トレードオフ
得られるのは、利用者が既に知っている動きで新しいリソースをすぐ使い始められることです。
引き換えに、標準の形にぴったり合わない操作を Create や Update に押し込めることになり、少し窮屈な場面が出てきます。
書籍は、まず標準メソッドで API の 9 割を作り、残りのどうしても合わない操作だけをカスタムメソッド（第 9 章）にする、という進め方を勧めています。

## 8. 参考
- 『APIデザイン・パターン』JJ Geewax 著、マイナビ出版、第 7 章
- https://google.aip.dev/130 （標準メソッドの一覧。Get は 131、List は 132、Create は 133、Update は 134、Delete は 135）
- AWS の API も、EC2 は `DescribeInstances`、S3 は `ListBuckets` と、一覧の動詞がサービスごとに違います。「1 つ覚えても次で使えない」が起きている例です: https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_DescribeInstances.html 、https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListBuckets.html
