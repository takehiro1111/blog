---
title: "[Go]APIデザインパターン 8: 部分的な更新と取り出し（使う/使わないの前後比較）"
emoji: "📘"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Go", "API", "設計", "デザインパターン"]
published: false
---
![](/images/go/go_logo.png =450x)

## 本記事の内容
- 『APIデザイン・パターン』(JJ Geewax 著、マイナビ出版) の第 8 章「部分的な更新と取り出し」を、Go で書き直しながら読んだメモです
- リソース全体を送って置き換える実装と、`fieldMask` で指定したフィールドだけを更新・取得する実装を同じ手順で動かして、何が変わるかを出力で確かめます
- コードは Go 1.22 以降の `net/http` と標準ライブラリだけで動きます
- シリーズの目次は「[Go]APIデザインパターン 00: 目次と、パターンを使わないとどうなるか」にあります

## 1. 結論
更新したい、または取り出したいフィールドの名前の一覧を `fieldMask` としてクエリ文字列で渡します。
`PATCH /chatRooms/1?fieldMask=title` なら `title` だけを更新し、`GET /chatRooms/1?fieldMask=title&fieldMask=loggingConfig.maxSizeMb` なら 2 つのフィールドだけが返ります。

PATCH で `fieldMask` を省略した時は、本文に書かれているフィールドを更新対象とみなします。
本文に `null` と書いたフィールドは対象に入り、書かなかったフィールドには触りません。
この「書かなかった」を Go で表すために、本文は struct ではなく `map[string]any` で受けます。

## 2. 困る場面
リソースを更新する手段が「全体を送って置き換える」しかないと、次のことが起きます。

- 利用者のクライアントが古く、サーバー側で後から増えた `description` を知らないと、`title` を直しただけのつもりで `description` を消してしまいます
- 2 人が同じリソースの別のフィールドを同時に直すと、後に送った方が前の人の変更を元に戻します。エラーは出ません

Go で素朴に部分更新を書こうとすると、もう 1 つ壁があります。
JSON を struct に入れると、本文に無かったフィールドはゼロ値（`""` や `0`）になり、「指定しなかった」のか「空にしたい」のかが区別できません。
ゼロ値を無視する実装にすると、今度はフィールドを空にできなくなります。
4-2 で、`description` が消える様子と、空にできない様子の両方を見ます。

## 3. 足すもの
増えるのは、Get と Update のリクエストに付く `fieldMask` と、それを本文に当てはめる処理です。

`fieldMask` はフィールドのパスの配列で、`?fieldMask=title&fieldMask=description` のように同じ名前のクエリパラメータを繰り返して渡します。
本文に入れないのは、GET には本文が無く、PATCH の本文はリソースそのものであるべきだからです。
入れ子のフィールドは `loggingConfig.maxSizeMb` のようにドットでつなぎ、`loggingConfig.*` でその下全部、`*` でリソース全部を指します。
`settings` のような動的な map のキーにドットや数字が入る時はバッククォートで囲む、という規則も書籍の 8.3.2 節にありますが、今回のコードでは扱っていません。

Get で `fieldMask` を省略した時は全フィールドを返します。
Update で省略した時は、本文に書かれたフィールドから推測します（暗黙のフィールドマスク）。
`null` も「書かれた」に入るので、`{"description": null}` は `description` を null にする指示です。
逆に `?fieldMask=settings.test` と指定して本文に `settings.test` を書かなければ、そのキーを消す指示になります。
JSON には「未定義」を表す値が無いので、消したい時はこの形を使います。

| 送り方 | 更新対象 | 結果 |
|---|---|---|
| `{"title":"New"}` | `title` | title を New にする |
| `{"description":null}` | `description` | description を null にする |
| `?fieldMask=settings.test` と `{}` | `settings.test` | settings から test を消す |
| 本文に書かない | （含まれない） | 触らない |

存在しないフィールド名が指定されても、エラーにはしません。
バージョンが進むとフィールドは増えたり減ったりするので、知らない名前は「値が無いフィールド」として扱います。

Go では、保存する形を JSON と同じ `map[string]any` にします。

```go
type ChatRoom struct { // ①
	ID            string         `json:"id"`
	Title         string         `json:"title"`
	Description   string         `json:"description"`
	LoggingConfig LoggingConfig  `json:"loggingConfig"`
	Settings      map[string]any `json:"settings"`
}

type LoggingConfig struct {
	MaxSizeMb       int `json:"maxSizeMb"`
	MaxMessageCount int `json:"maxMessageCount"`
}

type store struct {
	mu    sync.Mutex
	seq   int
	rooms map[string]map[string]any // ②
}
```

- ① 書籍のリスト 8.4 と同じ形です。`loggingConfig` は固定の入れ子、`settings` は何でも入る map です
- ② 作成時は `ChatRoom` で受けて形を確かめ、保存は JSON と同じ `map[string]any` にします

:::message
struct に JSON を入れると、無かったフィールドはゼロ値になります。
`*string` にしても、`null` と「無い」はどちらも `nil` なので、やはり 2 つしか区別できません。
`map[string]any` なら、キーが無い、キーがあって値が `nil`、値がある、の 3 つを保てます。
:::

## 4. 前後比較
### 4-1. 使わない場合
PUT で全体を置き換えるハンドラと、ゼロ値を無視する PATCH です。

```go
	mux.HandleFunc("PUT /chatRooms/{id}", func(w http.ResponseWriter, req *http.Request) {
		var in ChatRoom
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		s.mu.Lock()
		defer s.mu.Unlock()
		in.ID = req.PathValue("id")
		s.rooms[in.ID] = in // ①
		writeJSON(w, http.StatusOK, in)
	})

	mux.HandleFunc("PATCH /chatRooms/{id}", func(w http.ResponseWriter, req *http.Request) {
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
		if in.Title != "" { // ②
			room.Title = in.Title
		}
		if in.Description != "" {
			room.Description = in.Description
		}
		s.rooms[room.ID] = room
		writeJSON(w, http.StatusOK, room)
	})
```

- ① 本文に無かったフィールドはゼロ値のまま保存されます
- ② ゼロ値を「指定なし」とみなしています。空文字にしたい時の伝え方がありません

### 4-2. 動かすと description が消え、空にもできない
`title` と `description` を持つ部屋を作り、`description` を知らないクライアントが `title` だけを PUT します。

```
$ curl -s -i -X POST localhost:8008/chatRooms \
    -d '{"title":"Old title","description":"Cool chat"}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","title":"Old title","description":"Cool chat"}

$ curl -s -i -X PUT localhost:8008/chatRooms/1 -d '{"id":"1","title":"New title"}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","title":"New title","description":""}
```

`description` が消えました。
PATCH なら `description` を戻せますが、空にはできません。

```
$ curl -s -i -X PATCH localhost:8008/chatRooms/1 -d '{"description":"Cool chat"}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","title":"New title","description":"Cool chat"}

$ curl -s -i -X PATCH localhost:8008/chatRooms/1 -d '{"description":""}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","title":"New title","description":"Cool chat"}
```

### 4-3. 使う場合（差分）
PATCH の本文を `map[string]any` で受け、`fieldMask`（無ければ本文から推測したもの）のパスだけを当てはめます。

```diff go
 	mux.HandleFunc("PATCH /chatRooms/{id}", func(w http.ResponseWriter, req *http.Request) {
-		var in ChatRoom
+		var in map[string]any // ①
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
-		if in.Title != "" {
-			room.Title = in.Title
-		}
-		if in.Description != "" {
-			room.Description = in.Description
-		}
-		s.rooms[room.ID] = room
+		in["id"] = room["id"]
+		mask := req.URL.Query()["fieldMask"] // ②
+		if len(mask) == 0 {
+			mask = inferFieldMask(in, "") // ③
+		}
+		for _, p := range mask {
+			applyField(room, in, strings.Split(p, ".")) // ④
+		}
 		writeJSON(w, http.StatusOK, room)
 	})
```

- ① 本文を map で受けるので、キーが無い / `null` / 値あり を区別できます
- ② `?fieldMask=a&fieldMask=b` は `url.Values` がそのまま `[]string` にしてくれます
- ③ 省略時は本文のキーから推測します
- ④ パスごとに本文の値を当てはめます。`room` は map なので、その場で書き換わります

足した関数は 2 つです。

```go
func inferFieldMask(src map[string]any, prefix string) []string { // ①
	var mask []string
	for k, v := range src {
		if child, ok := v.(map[string]any); ok && len(child) > 0 {
			mask = append(mask, inferFieldMask(child, prefix+k+".")...)
			continue
		}
		mask = append(mask, prefix+k)
	}
	sort.Strings(mask)
	return mask
}

func applyField(dst, src map[string]any, path []string) { // ②
	key := path[0]
	if len(path) == 1 {
		if v, ok := src[key]; ok {
			dst[key] = v
		} else {
			delete(dst, key)
		}
		return
	}
	dstChild, _ := dst[key].(map[string]any)
	if dstChild == nil {
		dstChild = map[string]any{}
		dst[key] = dstChild
	}
	srcChild, _ := src[key].(map[string]any)
	applyField(dstChild, srcChild, path[1:])
}
```

- ① 書籍のリスト 8.7 と同じ考え方です。入れ子の map は再帰して `loggingConfig.maxSizeMb` の形にし、`nil`（JSON の `null`）もそのまま一覧に入れます
- ② パスの最後まで来たら、本文に値があれば代入、無ければキーを消します。途中の map が無ければ作ります

Get の側は、`fieldMask` があれば `pickFields` で必要なフィールドだけを集めます。

```diff go
 	mux.HandleFunc("GET /chatRooms/{id}", func(w http.ResponseWriter, req *http.Request) {
 		s.mu.Lock()
+		defer s.mu.Unlock()
 		room, ok := s.rooms[req.PathValue("id")]
-		s.mu.Unlock()
 		if !ok {
 			http.Error(w, "not found", http.StatusNotFound)
 			return
 		}
-		writeJSON(w, http.StatusOK, room)
+		mask := req.URL.Query()["fieldMask"]
+		if len(mask) == 0 { // ①
+			writeJSON(w, http.StatusOK, room)
+			return
+		}
+		writeJSON(w, http.StatusOK, pickFields(room, mask))
 	})
```

- ① 省略時は全フィールドです。`pickFields` は `*` が来たら全部返し、知らない名前は黙って飛ばします

:::message
`map[string]any` を `json.Marshal` すると、キーはアルファベット順に並びます。
4-4 の出力で `description` が先頭に来ているのはそのためで、struct の時のようなフィールド順にはなりません。
:::

:::details after/main.go の全文
```go
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
)

type ChatRoom struct {
	ID            string         `json:"id"`
	Title         string         `json:"title"`
	Description   string         `json:"description"`
	LoggingConfig LoggingConfig  `json:"loggingConfig"`
	Settings      map[string]any `json:"settings"`
}

type LoggingConfig struct {
	MaxSizeMb       int `json:"maxSizeMb"`
	MaxMessageCount int `json:"maxMessageCount"`
}

type store struct {
	mu    sync.Mutex
	seq   int
	rooms map[string]map[string]any // ①
}

func toMap(v any) map[string]any {
	b, _ := json.Marshal(v)
	var m map[string]any
	json.Unmarshal(b, &m)
	return m
}

func inferFieldMask(src map[string]any, prefix string) []string { // ②
	var mask []string
	for k, v := range src {
		if child, ok := v.(map[string]any); ok && len(child) > 0 {
			mask = append(mask, inferFieldMask(child, prefix+k+".")...)
			continue
		}
		mask = append(mask, prefix+k)
	}
	sort.Strings(mask)
	return mask
}

func applyField(dst, src map[string]any, path []string) { // ③
	key := path[0]
	if len(path) == 1 {
		if v, ok := src[key]; ok {
			dst[key] = v
		} else {
			delete(dst, key)
		}
		return
	}
	dstChild, _ := dst[key].(map[string]any)
	if dstChild == nil {
		dstChild = map[string]any{}
		dst[key] = dstChild
	}
	srcChild, _ := src[key].(map[string]any)
	applyField(dstChild, srcChild, path[1:])
}

func pickFields(src map[string]any, mask []string) map[string]any { // ④
	out := map[string]any{"id": src["id"]}
	for _, p := range mask {
		if p == "*" {
			return src
		}
		copyField(out, src, strings.Split(p, "."))
	}
	return out
}

func copyField(dst, src map[string]any, path []string) {
	key := path[0]
	v, ok := src[key]
	if !ok {
		return
	}
	if len(path) == 1 || path[1] == "*" {
		dst[key] = v
		return
	}
	srcChild, ok := v.(map[string]any)
	if !ok {
		return
	}
	dstChild, _ := dst[key].(map[string]any)
	if dstChild == nil {
		dstChild = map[string]any{}
		dst[key] = dstChild
	}
	copyField(dstChild, srcChild, path[1:])
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func main() {
	s := &store{rooms: map[string]map[string]any{}}
	mux := http.NewServeMux()

	mux.HandleFunc("POST /chatRooms", func(w http.ResponseWriter, req *http.Request) {
		var room ChatRoom
		if err := json.NewDecoder(req.Body).Decode(&room); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		s.mu.Lock()
		defer s.mu.Unlock()
		s.seq++
		room.ID = strconv.Itoa(s.seq)
		s.rooms[room.ID] = toMap(room)
		writeJSON(w, http.StatusOK, s.rooms[room.ID])
	})

	mux.HandleFunc("GET /chatRooms/{id}", func(w http.ResponseWriter, req *http.Request) {
		s.mu.Lock()
		defer s.mu.Unlock()
		room, ok := s.rooms[req.PathValue("id")]
		if !ok {
			http.Error(w, "not found", http.StatusNotFound)
			return
		}
		mask := req.URL.Query()["fieldMask"] // ⑤
		if len(mask) == 0 {
			writeJSON(w, http.StatusOK, room)
			return
		}
		writeJSON(w, http.StatusOK, pickFields(room, mask))
	})

	mux.HandleFunc("PATCH /chatRooms/{id}", func(w http.ResponseWriter, req *http.Request) {
		var in map[string]any
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
		in["id"] = room["id"]
		mask := req.URL.Query()["fieldMask"]
		if len(mask) == 0 {
			mask = inferFieldMask(in, "") // ⑥
		}
		for _, p := range mask {
			applyField(room, in, strings.Split(p, "."))
		}
		writeJSON(w, http.StatusOK, room)
	})

	log.Fatal(http.ListenAndServe(":8108", mux))
}
```
:::

### 4-4. 同じ手順で動かすと description が残り、null で空にでき、キーも消せる
入れ子の `loggingConfig` と map の `settings` を持つ部屋を作ってから、`title` だけを PATCH します。

```
$ curl -s -i -X POST localhost:8108/chatRooms \
    -d '{"title":"Old title","description":"Cool chat",
         "loggingConfig":{"maxSizeMb":10,"maxMessageCount":1000},
         "settings":{"test":"value","color":"red"}}'
HTTP/1.1 200 OK
Content-Type: application/json

{"description":"Cool chat","id":"1","loggingConfig":{"maxMessageCount":1000,"maxSizeMb":10},"settings":{"color":"red","test":"value"},"title":"Old title"}

$ curl -s -i -X PATCH localhost:8108/chatRooms/1 -d '{"title":"New title"}'
HTTP/1.1 200 OK
Content-Type: application/json

{"description":"Cool chat","id":"1","loggingConfig":{"maxMessageCount":1000,"maxSizeMb":10},"settings":{"color":"red","test":"value"},"title":"New title"}
```

`description` は残っています。
`null` を送ると空になり、`fieldMask` で名前だけ指定して本文を空にすると map のキーが消えます。
入れ子の片方だけ送っても、もう片方は残ります。

```
$ curl -s -i -X PATCH localhost:8108/chatRooms/1 -d '{"description":null}'
HTTP/1.1 200 OK
Content-Type: application/json

{"description":null,"id":"1","loggingConfig":{"maxMessageCount":1000,"maxSizeMb":10},"settings":{"color":"red","test":"value"},"title":"New title"}

$ curl -s -i -X PATCH 'localhost:8108/chatRooms/1?fieldMask=settings.test' -d '{}'
HTTP/1.1 200 OK
Content-Type: application/json

{"description":null,"id":"1","loggingConfig":{"maxMessageCount":1000,"maxSizeMb":10},"settings":{"color":"red"},"title":"New title"}

$ curl -s -i -X PATCH localhost:8108/chatRooms/1 -d '{"loggingConfig":{"maxSizeMb":20}}'
HTTP/1.1 200 OK
Content-Type: application/json

{"description":null,"id":"1","loggingConfig":{"maxMessageCount":1000,"maxSizeMb":20},"settings":{"color":"red"},"title":"New title"}
```

取得は、指定したフィールドだけが返ります。
知らない名前を指定してもエラーにはならず、`id` だけが返ります。

```
$ curl -s -i \
    'localhost:8108/chatRooms/1?fieldMask=title&fieldMask=loggingConfig.maxSizeMb'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","loggingConfig":{"maxSizeMb":20},"title":"New title"}

$ curl -s -i 'localhost:8108/chatRooms/1?fieldMask=noSuchField'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1"}
```

## 5. 1 リクエストの流れ
`PATCH /chatRooms/1` に `{"title":"New title"}` を送った時の流れです。

1. 利用者が `fieldMask` なしで PATCH を送る
2. サーバーは本文を `map[string]any` に入れる。読めなければ 400
3. `map` から部屋 `1` を引く。無ければ 404
4. 本文の `id` をパスの値で上書きしてから、クエリに `fieldMask` が無いので本文のキーから `["id", "title"]` を推測する
5. パスごとに `applyField` を呼ぶ。`title` は本文にあるので代入する
6. 更新後の部屋全体を 200 で返す

`?fieldMask=settings.test` と `{}` の組み合わせなら、4 で推測をせず、5 で `settings` の中に `test` が無いのでキーを消します。

## 6. 疑問と答え
読みながら引っかかったところです。

**なぜ `fieldMask` を本文ではなくクエリ文字列で送るのか**
GET には本文が無く、PATCH の本文はリソースそのものであるべきだからです。
残る置き場所はヘッダーかクエリで、ブラウザからも扱いやすいクエリを書籍は選んでいます。
`fieldMask=a,b` とカンマで区切る形は map のキーを扱う時に壊れやすいので、同じ名前を繰り返す形にします。

**`null` と「書かない」は何が違うのか**
`null` は「このフィールドを null にせよ」という値で、更新対象に入ります。
書かないのは「触らない」です。
Go の struct ではこの 2 つが同じ `""` や `nil` になるので、map で受けています。

**map のキーを消すにはどうするのか**
`?fieldMask=settings.test` のようにパスを指定し、本文にはそのキーを書きません。
JSON には「未定義」を表す値が無いので、`null` ではなく「指定したのに無い」で消す意思を伝えます。

**配列の 3 番目だけを更新できないのか**
できないようにします。
順番が安定している保証がなく、間に 1 件挿入されただけで別の要素を書き換えてしまうからです。
配列は丸ごと置き換えるか、安定した識別子を持つ map やサブリソースにします。
取得の時だけは `administrators.*.name` のように「各要素の name」を指定できます。

**知らないフィールド名が来たらエラーにしなくてよいのか**
エラーにしません。
古いクライアントが、今はもう無いフィールドを指定してくることは普通に起きます。
値が無いフィールドとして扱い、更新も取得も続けます。

**JSON Patch や JSON Merge Patch ではいけないのか**
どちらも使えます。
JSON Merge Patch は暗黙のフィールドマスクに近い仕組みですが、`null` にすることとキーを消すことを区別できず、配列の中には再帰しません。
JSON Patch は操作の列を送る方式で、より細かい制御が要る時の選択肢です。

ここまでを自分の言葉でまとめると、「どのフィールドの話をしているか」を `fieldMask` で明示し、省略時は本文に書いたものだけを対象にする、`null` は対象で「書かない」は対象外、です。

## 7. トレードオフ
得られるのは、他の利用者や古いクライアントの知らないフィールドを壊さずに 1 つのフィールドだけ直せることと、必要なフィールドだけ受け取って転送量を減らせることです。
引き換えに、ドット区切りやバッククォートの規則、繰り返しのクエリパラメータの扱いなど、サーバーとクライアントの両方に覚えることが増えます。

書籍は、部分更新は Update に必ず入れ、部分取得は要るなら全リソースでそろえて提供する、という進め方を勧めています。
関連するリソースをまたいで必要なデータだけ取りたい、という用途には `fieldMask` ではなく GraphQL のような仕組みが向いている、とも書いています。

## 8. 参考
- 『APIデザイン・パターン』JJ Geewax 著、マイナビ出版、第 8 章
- https://google.aip.dev/134 、https://google.aip.dev/157 、https://google.aip.dev/161
- DynamoDB の `UpdateItem` は、`UpdateExpression` に `SET` で書いた属性だけを変え、`REMOVE` で属性を消します。「指定したものだけ触る」「消す指示を別に持つ」がこの章と同じ考え方です: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Expressions.UpdateExpressions.html
