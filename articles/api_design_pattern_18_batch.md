---
title: "[Go]APIデザインパターン 18: バッチ操作（使う/使わないの前後比較）"
emoji: "📘"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Go", "API", "設計", "デザインパターン"]
published: false
---
![](/images/go/go_logo.png =450x)

## 本記事の内容
- 『APIデザイン・パターン』(JJ Geewax 著、マイナビ出版) の第 18 章「バッチ操作」を、Go で書き直しながら読んだメモです
- パターンを使わない実装と使う実装を同じ手順で動かして、何が変わるかを出力で確かめます
- コードは Go 1.22 以降の `net/http` と標準ライブラリだけで動きます
- シリーズの目次は「[Go]APIデザインパターン 00: 目次と、パターンを使わないとどうなるか」にあります

## 1. 結論
複数のリソースをまとめて扱いたい時は、標準メソッドを何回も呼ぶのではなく、`BatchCreateMessages` や `BatchDeleteMessages` のようなバッチ版のカスタムメソッドを 1 回呼びます。
バッチメソッドは全部成功するか全部失敗するかのどちらかで、途中まで成功した状態を残しません。
結果は、送った順と同じ順で返します。

## 2. 困る場面
Message を 3 件作りたいとします。
標準の create を 3 回呼ぶと、2 件目が失敗しても 1 件目は作られたままです。
利用者は「どこまで成功したか」を自分で調べ、残りを消すのかやり直すのかを決めることになります。

削除も同じです。
3 件のうち 1 件が存在しなければ、残りの 2 件だけが消えて 1 件は 404 になります。
データベースならトランザクションで「全部か、無しか」にできますが、Web API には普通そういう仕組みがありません。
4-2 で、途中まで成功した状態を見ます。

## 3. 足すもの
バッチメソッドは get / create / update / delete の 4 つで、list のバッチ版はありません。
この記事では create と delete の 2 つを書きます。

| メソッド | HTTP | 入力 | 出力 |
|---|---|---|---|
| `:batchGet` | GET | `ids`（クエリ文字列） | `resources` |
| `:batchCreate` | POST | `requests`（create リクエストの配列） | `resources` |
| `:batchUpdate` | POST | `requests`（update リクエストの配列）と `fieldMask` | `resources` |
| `:batchDelete` | POST | `ids` | 無し |

URL は親リソースではなくコレクションを対象にします。
`/chatRooms/1:batchUpdateMessages` ではなく `/chatRooms/1/messages:batchUpdate` です。
HTTP メソッドは、べき等な batchGet だけ GET で、それ以外はカスタムメソッドの決まりどおり POST を使います。
batchUpdate も、標準の update が PATCH なのに対して POST です。

入力の形が 2 通りあるのは、書籍の 18.3.4 で説明されている使い分けです。
get と delete は識別子しか要らないので `ids` の配列を直接受け取ります。
create は各リソースの親が要るので、標準の create リクエスト（`parent` と `resource`）の配列を受け取ります。
複数の親にまたがって作りたい時は URL の親に `-` を書き、各リクエストの `parent` で実際の親を指定します。
URL に具体的な親を書いたのに各リクエストの `parent` がそれと違う場合は、意図を推測せずに 400 で拒否します。

レスポンスの `resources` は、リクエストと同じ順に並べます。
サーバーが識別子を決める API では、順序が崩れると「送ったどれが、返ってきたどれか」を突き合わせる手段が無くなるからです。
batchDelete は返すものが無いので、本文無しの 204 No Content にしました。

1 回に受け付ける件数には上限を決めてドキュメントに書きます。
バッチメソッドにはページ分割を入れません。

Go の型にするとこうなります。

```go
type CreateMessageRequest struct {
	Parent   string  `json:"parent,omitempty"` // ①
	Resource Message `json:"resource"`
}

type BatchCreateMessagesRequest struct {
	Requests []CreateMessageRequest `json:"requests"` // ②
}

type BatchCreateMessagesResponse struct {
	Resources []Message `json:"resources"` // ③
}

type BatchDeleteMessagesRequest struct {
	IDs []string `json:"ids"` // ④
}

const maxBatchSize = 100

const wildcardParent = "chatRooms/-"
```

- ① 標準の create リクエストです。URL の親が `-` の時は、ここで親を指定します
- ② リソースの配列ではなく、create リクエストの配列です
- ③ `requests` と同じ順に並びます
- ④ delete は識別子だけで足りるので、配列を直接持ちます

## 4. 前後比較
### 4-1. 使わない場合
標準の create と delete だけの API です。
利用者が件数ぶん呼びます。

```go
mux.HandleFunc("POST /chatRooms/{room}/messages", func(w http.ResponseWriter, req *http.Request) {
	var in CreateMessageRequest
	if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
		http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
		return
	}
	parent := "chatRooms/" + req.PathValue("room")
	s.mu.Lock()
	defer s.mu.Unlock()
	room, ok := s.rooms[parent]
	if !ok {
		http.Error(w, parent+" not found", http.StatusNotFound)
		return
	}
	if utf8.RuneCountInString(in.Resource.Content) > room.MessageLengthLimit {
		http.Error(w, "content exceeds messageLengthLimit", http.StatusBadRequest)
		return
	}
	s.seq++
	in.Resource.ID = parent + "/messages/" + strconv.Itoa(s.seq)
	s.messages = append(s.messages, in.Resource) // ①
	writeJSON(w, http.StatusOK, in.Resource)
})

mux.HandleFunc("DELETE /chatRooms/{room}/messages/{msg}", func(w http.ResponseWriter, req *http.Request) {
	id := "chatRooms/" + req.PathValue("room") + "/messages/" + req.PathValue("msg")
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, m := range s.messages {
		if m.ID == id {
			s.messages = append(s.messages[:i], s.messages[i+1:]...) // ②
			w.WriteHeader(http.StatusNoContent)
			return
		}
	}
	http.Error(w, id+" not found", http.StatusNotFound)
})
```

- ① 1 リクエストで 1 件作ります。前後のリクエストのことは知りません
- ② 1 リクエストで 1 件消します

:::message
`append(s.messages[:i], s.messages[i+1:]...)` は、スライスから i 番目を取り除く Go の定番の書き方です。
`s.messages[:i]` の後ろに `i+1` 番目以降を詰め直しています。
:::

### 4-2. 動かすと途中まで成功した状態が残る
`a`、120 文字の `xxx…`、`c` の 3 件を順に作ります。
ChatRoom の `messageLengthLimit` は 100 なので、2 件目だけが通りません。

```
$ curl -s -i -X POST localhost:8018/chatRooms/1/messages \
    -d '{"resource":{"content":"a"}}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"chatRooms/1/messages/1","content":"a"}

$ curl -s -i -X POST localhost:8018/chatRooms/1/messages \
    -d '{"resource":{"content":"xxxxxxxx..."}}'
HTTP/1.1 400 Bad Request
Content-Type: text/plain; charset=utf-8

content exceeds messageLengthLimit

$ curl -s -i -X POST localhost:8018/chatRooms/1/messages \
    -d '{"resource":{"content":"c"}}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"chatRooms/1/messages/2","content":"c"}

$ curl -s localhost:8018/chatRooms/1/messages
{"results":[{"id":"chatRooms/1/messages/1","content":"a"},{"id":"chatRooms/1/messages/2","content":"c"}]}
```

`a` と `c` だけが作られました。
削除も、存在しない `99` を混ぜると他の 2 件だけ消えます。

```
$ curl -s -i -X DELETE localhost:8018/chatRooms/1/messages/1
HTTP/1.1 204 No Content

$ curl -s -i -X DELETE localhost:8018/chatRooms/1/messages/99
HTTP/1.1 404 Not Found
Content-Type: text/plain; charset=utf-8

chatRooms/1/messages/99 not found

$ curl -s -i -X DELETE localhost:8018/chatRooms/1/messages/2
HTTP/1.1 204 No Content

$ curl -s localhost:8018/chatRooms/1/messages
{"results":[]}
```

### 4-3. 使う場合（差分）
保存場所はそのままで、`batchCreate` をサーバーに足します。
「先に全部確かめてから、まとめて書き換える」の 2 段構えです。

```diff go
+func (s *store) batchCreate(urlParent string, reqs []CreateMessageRequest) ([]Message, error) {
+	s.mu.Lock()
+	defer s.mu.Unlock()
+	if len(reqs) == 0 || len(reqs) > maxBatchSize {
+		return nil, fail(http.StatusBadRequest, "requests must have 1..%d items", maxBatchSize)
+	}
+	for i, r := range reqs { // ①
+		parent := r.Parent
+		if urlParent != wildcardParent {
+			if parent == "" {
+				parent = urlParent
+			} else if parent != urlParent {
+				return nil, fail(http.StatusBadRequest, "requests[%d].parent %q conflicts with URL parent %q", i, parent, urlParent)
+			}
+		}
+		room, ok := s.rooms[parent]
+		if !ok {
+			return nil, fail(http.StatusNotFound, "requests[%d]: parent %q not found", i, parent)
+		}
+		if utf8.RuneCountInString(r.Resource.Content) > room.MessageLengthLimit {
+			return nil, fail(http.StatusBadRequest, "requests[%d]: content exceeds messageLengthLimit", i)
+		}
+		reqs[i].Parent = parent
+	}
+	out := make([]Message, 0, len(reqs))
+	for _, r := range reqs { // ②
+		s.seq++
+		m := r.Resource
+		m.ID = r.Parent + "/messages/" + strconv.Itoa(s.seq)
+		s.messages = append(s.messages, m)
+		out = append(out, m)
+	}
+	return out, nil
+}
+
 func main() {
 	s := seed()
 	mux := http.NewServeMux()
 
-	mux.HandleFunc("POST /chatRooms/{room}/messages", func(w http.ResponseWriter, req *http.Request) {
+	mux.HandleFunc("POST /chatRooms/{room}/messages:batchCreate", func(w http.ResponseWriter, req *http.Request) {
+		var in BatchCreateMessagesRequest
+		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
+			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
+			return
+		}
+		created, err := s.batchCreate("chatRooms/"+req.PathValue("room"), in.Requests)
+		if err != nil {
+			writeError(w, err)
+			return
+		}
+		writeJSON(w, http.StatusOK, BatchCreateMessagesResponse{Resources: created}) // ③
+	})
```

- ① 1 周目は確認だけです。親の食い違い、親の有無、長さの制約を全件見て、1 つでも駄目ならここで返ります。この時点では何も書き換えていません
- ② 2 周目で、送られた順に作って同じ順で `out` に積みます
- ③ `resources` に、送られた順のまま入れて返します

`batchDelete` も同じ 2 段構えで、1 周目で全件の存在を確かめ、1 つでも無ければ何も消さずに 404 を返します。
返すものが無いので、成功時は 204 No Content です。
コードは下の全文に載せています。

:::message
ハンドラの中で `s.mu.Lock()` から `defer s.mu.Unlock()` までの間は、他のリクエストが保存場所に触れません。
この記事では、その区間がそのまま「全部成功か全部失敗か」の単位になっています。
データベースを使う実装では、この区間をトランザクションに置き換えることになります。
:::

:::message
`ServeMux` のパターンは `messages:batchCreate` のように、固定の文字列なら `:` を含んでいても登録できます。
第 17 章の `{id}:move` のようにワイルドカードの直後に付けることができないだけです。
:::

全文は畳んでおきます。

:::details after/main.go の全文
```go
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"unicode/utf8"
)

type ChatRoom struct {
	ID                 string `json:"id"`
	MessageLengthLimit int    `json:"messageLengthLimit"`
}

type Message struct {
	ID      string `json:"id"`
	Content string `json:"content"`
}

type CreateMessageRequest struct {
	Parent   string  `json:"parent,omitempty"`
	Resource Message `json:"resource"`
}

type BatchCreateMessagesRequest struct {
	Requests []CreateMessageRequest `json:"requests"`
}

type BatchCreateMessagesResponse struct {
	Resources []Message `json:"resources"`
}

type BatchDeleteMessagesRequest struct {
	IDs []string `json:"ids"`
}

const maxBatchSize = 100

const wildcardParent = "chatRooms/-"

type apiError struct {
	status int
	msg    string
}

func (e *apiError) Error() string { return e.msg }

func fail(status int, format string, a ...any) error {
	return &apiError{status: status, msg: fmt.Sprintf(format, a...)}
}

type store struct {
	mu       sync.Mutex
	seq      int
	rooms    map[string]ChatRoom
	messages []Message
}

func seed() *store {
	return &store{rooms: map[string]ChatRoom{
		"chatRooms/1": {ID: "chatRooms/1", MessageLengthLimit: 100},
		"chatRooms/2": {ID: "chatRooms/2", MessageLengthLimit: 100},
	}}
}

func (s *store) batchCreate(urlParent string, reqs []CreateMessageRequest) ([]Message, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(reqs) == 0 || len(reqs) > maxBatchSize {
		return nil, fail(http.StatusBadRequest, "requests must have 1..%d items", maxBatchSize)
	}
	for i, r := range reqs {
		parent := r.Parent
		if urlParent != wildcardParent {
			if parent == "" {
				parent = urlParent
			} else if parent != urlParent {
				return nil, fail(http.StatusBadRequest, "requests[%d].parent %q conflicts with URL parent %q", i, parent, urlParent)
			}
		}
		room, ok := s.rooms[parent]
		if !ok {
			return nil, fail(http.StatusNotFound, "requests[%d]: parent %q not found", i, parent)
		}
		if utf8.RuneCountInString(r.Resource.Content) > room.MessageLengthLimit {
			return nil, fail(http.StatusBadRequest, "requests[%d]: content exceeds messageLengthLimit", i)
		}
		reqs[i].Parent = parent
	}
	out := make([]Message, 0, len(reqs))
	for _, r := range reqs {
		s.seq++
		m := r.Resource
		m.ID = r.Parent + "/messages/" + strconv.Itoa(s.seq)
		s.messages = append(s.messages, m)
		out = append(out, m)
	}
	return out, nil
}

func (s *store) batchDelete(urlParent string, ids []string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(ids) == 0 || len(ids) > maxBatchSize {
		return fail(http.StatusBadRequest, "ids must have 1..%d items", maxBatchSize)
	}
	index := map[string]int{}
	for i, m := range s.messages {
		index[m.ID] = i
	}
	for i, id := range ids {
		if urlParent != wildcardParent && !strings.HasPrefix(id, urlParent+"/messages/") {
			return fail(http.StatusBadRequest, "ids[%d] %q does not belong to %q", i, id, urlParent)
		}
		if _, ok := index[id]; !ok {
			return fail(http.StatusNotFound, "ids[%d] %q not found", i, id)
		}
	}
	remain := s.messages[:0]
	for _, m := range s.messages {
		if _, del := index[m.ID]; del && contains(ids, m.ID) {
			continue
		}
		remain = append(remain, m)
	}
	s.messages = remain
	return nil
}

func contains(ids []string, id string) bool {
	for _, x := range ids {
		if x == id {
			return true
		}
	}
	return false
}

func (s *store) list(parent string) []Message {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []Message{}
	for _, m := range s.messages {
		if strings.HasPrefix(m.ID, parent+"/messages/") {
			out = append(out, m)
		}
	}
	return out
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, err error) {
	var ae *apiError
	if errors.As(err, &ae) {
		http.Error(w, ae.msg, ae.status)
		return
	}
	http.Error(w, err.Error(), http.StatusInternalServerError)
}

func main() {
	s := seed()
	mux := http.NewServeMux()

	mux.HandleFunc("POST /chatRooms/{room}/messages:batchCreate", func(w http.ResponseWriter, req *http.Request) {
		var in BatchCreateMessagesRequest
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		created, err := s.batchCreate("chatRooms/"+req.PathValue("room"), in.Requests)
		if err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, BatchCreateMessagesResponse{Resources: created})
	})

	mux.HandleFunc("POST /chatRooms/{room}/messages:batchDelete", func(w http.ResponseWriter, req *http.Request) {
		var in BatchDeleteMessagesRequest
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		if err := s.batchDelete("chatRooms/"+req.PathValue("room"), in.IDs); err != nil {
			writeError(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})

	mux.HandleFunc("GET /chatRooms/{room}/messages", func(w http.ResponseWriter, req *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{"results": s.list("chatRooms/" + req.PathValue("room"))})
	})

	log.Fatal(http.ListenAndServe(":8118", mux))
}
```
:::

### 4-4. 同じ手順で動かすと全部成功か全部失敗になる
4-2 と同じ 3 件を 1 回の `:batchCreate` で送ります。

```
$ curl -s -i -X POST localhost:8118/chatRooms/1/messages:batchCreate \
    -d '{"requests":[{"resource":{"content":"a"}},
                     {"resource":{"content":"xxxxxxxx..."}},
                     {"resource":{"content":"c"}}]}'
HTTP/1.1 400 Bad Request
Content-Type: text/plain; charset=utf-8

requests[1]: content exceeds messageLengthLimit

$ curl -s localhost:8118/chatRooms/1/messages
{"results":[]}
```

2 件目が駄目なので、1 件目も作られていません。
エラー文に `requests[1]` と出るので、利用者はどれを直せばよいか分かります。
3 件とも正しければ、送った順に識別子が付いて返ってきます。

```
$ curl -s -i -X POST localhost:8118/chatRooms/1/messages:batchCreate \
    -d '{"requests":[{"resource":{"content":"a"}},
                     {"resource":{"content":"b"}},
                     {"resource":{"content":"c"}}]}'
HTTP/1.1 200 OK
Content-Type: application/json

{"resources":[{"id":"chatRooms/1/messages/1","content":"a"},{"id":"chatRooms/1/messages/2","content":"b"},{"id":"chatRooms/1/messages/3","content":"c"}]}
```

URL の親を `-` にすると、各リクエストの `parent` で別々の ChatRoom に作れます。
URL に `chatRooms/1` と書きながら `parent` に `chatRooms/2` を入れると、推測せずに 400 です。

```
$ curl -s -i -X POST 'localhost:8118/chatRooms/-/messages:batchCreate' \
    -d '{"requests":[{"parent":"chatRooms/1","resource":{"content":"d"}},
                     {"parent":"chatRooms/2","resource":{"content":"e"}}]}'
HTTP/1.1 200 OK
Content-Type: application/json

{"resources":[{"id":"chatRooms/1/messages/4","content":"d"},{"id":"chatRooms/2/messages/5","content":"e"}]}

$ curl -s -i -X POST localhost:8118/chatRooms/1/messages:batchCreate \
    -d '{"requests":[{"parent":"chatRooms/2","resource":{"content":"f"}}]}'
HTTP/1.1 400 Bad Request
Content-Type: text/plain; charset=utf-8

requests[0].parent "chatRooms/2" conflicts with URL parent "chatRooms/1"
```

削除も同じで、存在しない `99` を混ぜると 1 件も消えません。

```
$ curl -s -i -X POST localhost:8118/chatRooms/1/messages:batchDelete \
    -d '{"ids":["chatRooms/1/messages/1","chatRooms/1/messages/99",
               "chatRooms/1/messages/2"]}'
HTTP/1.1 404 Not Found
Content-Type: text/plain; charset=utf-8

ids[1] "chatRooms/1/messages/99" not found

$ curl -s localhost:8118/chatRooms/1/messages
{"results":[{"id":"chatRooms/1/messages/1","content":"a"},{"id":"chatRooms/1/messages/2","content":"b"},{"id":"chatRooms/1/messages/3","content":"c"},{"id":"chatRooms/1/messages/4","content":"d"}]}

$ curl -s -i -X POST localhost:8118/chatRooms/1/messages:batchDelete \
    -d '{"ids":["chatRooms/1/messages/1","chatRooms/1/messages/2"]}'
HTTP/1.1 204 No Content

$ curl -s localhost:8118/chatRooms/1/messages
{"results":[{"id":"chatRooms/1/messages/3","content":"c"},{"id":"chatRooms/1/messages/4","content":"d"}]}
```

## 5. 1 リクエストの流れ
本番で `:batchCreate` のリクエストがサーバーの中をどう通るかを、順に追います。
送る側を利用者、受ける側をサーバーと呼びます。

1. 利用者が `POST /chatRooms/1/messages:batchCreate` に `requests` の配列を送る
2. サーバーは本文を `BatchCreateMessagesRequest` に入れる。読めなければ 400
3. ロックを取る。8 まで他のリクエストは割り込めない
4. 件数が 1 以上、上限以下かを見る。外れていれば 400
5. 全件を順に確かめる。URL の親が `-` でないのに `parent` が食い違えば 400、親が無ければ 404、長さが制約を超えていれば 400。どれか 1 つでも当たれば、ここで返る
6. 全件通ったら、送られた順に識別子を付けて保存し、同じ順で配列に積む
7. ロックを解放する
8. `resources` に配列を入れて 200 で返す

## 6. 疑問と答え
読みながら引っかかったところです。

**なぜ list のバッチ版は無いのか**
list はもともと複数のリソースを返すメソッドなので、バッチにする意味がありません。
「条件に合うものをまとめて取りたい」なら、list にフィルターを付ける方が向いています。

**batchGet で 100 件中 1 件だけ無い時も、全体を失敗させるのか**
させます。
存在するものだけ返してほしいなら、それは batchGet ではなく、フィルター付きの list の仕事です。
書籍の 18.3.6 がこの使い分けを書いています。

**すでに消えているリソースを batchDelete に含めたら**
全体が失敗します。
削除は「無い状態にしてくれ」という宣言ではなく「この操作で消す」という命令として扱うので、自分の操作で消したと言えなければ成功にしません。

**なぜ結果の順序がそこまで大事なのか**
サーバーが識別子を決める API では、返ってきたリソースと送ったリソースを突き合わせる手がかりが順序しかありません。
順序が崩れると、識別子以外の全フィールドを比べて探すことになります。

**batchCreate はなぜリソースの配列ではなく、リクエストの配列を受け取るのか**
リソースの親は普通リソース自身のフィールドには無く、create リクエストの `parent` にあります。
複数の親にまたがって作れるようにするには、親を持てる単位、つまり create リクエストを並べる必要があります。

**1 回に何件まで送れるのか**
API ごとに上限を決めてドキュメントに書きます。
バッチのレスポンスにページ分割を入れてはいけないので、上限で大きさを抑えます。

ここまでを自分の言葉でまとめると、バッチメソッドは「全部か無しか」を保証する代わりに部分成功を一切返さず、結果は送った順、親をまたぐなら URL に `-` を書く、です。

## 7. トレードオフ
得られるのは、複数リソースへの操作を 1 リクエストで、しかもデータベースのトランザクションに近い「全部か無しか」で行えることです。
引き換えに、100 件中 1 件が駄目なだけで全体が失敗するので、場合によっては不便です。
部分成功を返す設計にすると、どれが成功しどれが失敗したかを表すレスポンスが要り、インターフェースが複雑になるため、書籍は不便でもアトミックを選んでいます。

入力の形が get / delete は `ids`、create / update は `requests` と揃っていないのも、一貫性より単純さを取った結果です。
すべてをリクエストの配列にすることもできますが、識別子を渡すだけのために遠回りになります。

## 8. 参考
- 『APIデザイン・パターン』JJ Geewax 著、マイナビ出版、第 18 章
- https://google.aip.dev/231 （Batch methods: Get）、https://google.aip.dev/233 （Create）、https://google.aip.dev/234 （Update）、https://google.aip.dev/235 （Delete）
- Amazon DynamoDB の `BatchWriteItem` は、個々の `PutItem` / `DeleteItem` はアトミックですが全体はアトミックではなく、処理できなかった分が `UnprocessedItems` で返ります。1 回に 25 件までです。書籍のバッチメソッドとは逆の設計なので、比べると違いが分かりやすいです: https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_BatchWriteItem.html
