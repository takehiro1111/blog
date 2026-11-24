---
title: "[Go]APIデザインパターン 17: コピーと移動（使う/使わないの前後比較）"
emoji: "📘"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Go", "API", "設計", "デザインパターン"]
published: false
---
![](/images/go/go_logo.png =450x)

## 本記事の内容
- 『APIデザイン・パターン』(JJ Geewax 著、マイナビ出版) の第 17 章「コピーと移動」を、Go で書き直しながら読んだメモです
- パターンを使わない実装と使う実装を同じ手順で動かして、何が変わるかを出力で確かめます
- コードは Go 1.22 以降の `net/http` と標準ライブラリだけで動きます
- シリーズの目次は「[Go]APIデザインパターン 00: 目次と、パターンを使わないとどうなるか」にあります

## 1. 結論
リソースを別の親に移したり複製したりする操作は、標準メソッドの組み合わせではなく `:move` と `:copy` というカスタムメソッドにします。
識別子をどう決めるか、子リソースをどうするか、参照をどう直すか、親から継承する制約に合わない時どうするか、途中で失敗したらどうするか。
これらをサーバー側で 1 回の処理として引き受けるのが、このパターンです。

ただし move が必要になる場面の多くは、識別子や親子関係の設計を間違えた後始末です。
書籍も、move を実装する前にリソースのレイアウトを見直すことを勧めています。

## 2. 困る場面
間違った ChatRoom の下に作ってしまった Message を、正しい ChatRoom に移したいとします。
API に標準メソッドしか無ければ、利用者は Get → Create → Delete を自分で並べて移すことになります。
一見それで済みそうですが、実際にやると 3 つの問題が出ます。

- Create で作り直すので識別子が変わります。`chatRooms/1/messages/abcd` が `chatRooms/2/messages/1` になります
- 元の Message を指していた別のリソース（この章では MessageReviewReport の `messageId`）が、もう存在しない識別子を指したままになります
- 3 リクエストの途中で止まると、両方の ChatRoom に Message がある状態や、どちらにも無い状態で終わります

4-2 で、実際に参照が切れるところを見ます。

## 3. 足すもの
カスタムメソッドを 2 つ足します。
`POST /chatRooms/{room}/messages/{id}:move` は移動先の識別子 `destinationId` を受け取り、移動後の Message を返します。
`POST /chatRooms/{id}:copy` は ChatRoom を子の Message ごと複製し、新しい ChatRoom を返します。

メソッドの形より大事なのが、書籍の 17.3 で決めている振る舞いです。

| 論点 | move | copy |
|---|---|---|
| 識別子 | `destinationId` で指定。親の部分だけ変えられる | create と同じくサーバーが決める |
| 子リソース | 一緒に移す | 一緒に複製する |
| 参照している他のリソース | 新しい識別子に書き換える | 複製するかは API ごとに決める |
| 外部データ（バイト列） | 動かさない | 参照だけ複製し、書き換え時に実体を複製する |
| 移動先の親の制約 | 合わなければ拒否する | 同じ |
| 途中の失敗 | 何も変えずに終える | 同じ |

「親の部分だけ変えられる」のは、この API がサーバー側で識別子を決めているからです。
利用者が識別子を指定できる API なら、move で名前の変更もできます。

ステータスコードは、移動先の識別子が使用済みなら 409 Conflict、元のリソースや移動先の親が無ければ 404 Not Found、`destinationId` の形式違反と制約違反は 400 Bad Request にしました。
制約違反のステータスは書籍が決めていないので、私の選択です。

Go の型にするとこうなります。

```go
type ChatRoom struct {
	ID                 string `json:"id"`
	Title              string `json:"title"`
	MessageLengthLimit int    `json:"messageLengthLimit"` // ①
}

type Message struct {
	ID      string `json:"id"` // ②
	Content string `json:"content"`
}

type MessageReviewReport struct {
	ID        string `json:"id"`
	MessageID string `json:"messageId"` // ③
	Reason    string `json:"reason"`
}

type MoveMessageRequest struct {
	DestinationID string `json:"destinationId"`
}

type apiError struct { // ④
	status int
	msg    string
}

func (e *apiError) Error() string { return e.msg }

func fail(status int, msg string) error { return &apiError{status: status, msg: msg} }
```

- ① 子の Message が継承する制約です
- ② `chatRooms/1/messages/abcd` のように、親を含んだ識別子です
- ③ Message への参照です。move の時にここを書き換えます
- ④ ステータスコードを持つ error です

:::message
Go の error は `Error() string` を持つ値なら何でもよいので、ステータスコードを一緒に持たせた `*apiError` を作っています。
ハンドラ側は `errors.As(err, &ae)` で `*apiError` を取り出し、その `status` で `http.Error` を呼びます。
取り出せない error は 500 Internal Server Error にします。
:::

## 4. 前後比較
### 4-1. 使わない場合
標準メソッドだけの API です。
利用者が Get → Create → Delete を順に呼んで移します。

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
	in.Resource.ID = parent + "/messages/" + strconv.Itoa(s.seq) // ①
	s.messages[in.Resource.ID] = in.Resource
	writeJSON(w, http.StatusOK, in.Resource)
})

mux.HandleFunc("DELETE /chatRooms/{room}/messages/{msg}", func(w http.ResponseWriter, req *http.Request) {
	id := "chatRooms/" + req.PathValue("room") + "/messages/" + req.PathValue("msg")
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.messages[id]; !ok {
		http.Error(w, id+" not found", http.StatusNotFound)
		return
	}
	delete(s.messages, id) // ②
	w.WriteHeader(http.StatusNoContent)
})
```

- ① create はサーバーが新しい識別子を決めます。元の識別子は引き継げません
- ② delete は Message を消すだけで、その Message を指している MessageReviewReport は見ていません

:::message
`req.PathValue("room")` は Go 1.22 で入った機能で、パスの `{room}` に一致した部分を返します。
:::

### 4-2. 動かすと参照が切れる
`chatRooms/1/messages/abcd` を `chatRooms/2` に移します。
起動時のデータとして、MessageReviewReport `reviewReports/1` がこの Message を指しています。

```
$ curl -s localhost:8017/chatRooms/1/messages/abcd
{"id":"chatRooms/1/messages/abcd","content":"hello"}

$ curl -s -X POST localhost:8017/chatRooms/2/messages \
    -d '{"resource":{"content":"hello"}}'
{"id":"chatRooms/2/messages/1","content":"hello"}

$ curl -s -i -X DELETE localhost:8017/chatRooms/1/messages/abcd
HTTP/1.1 204 No Content

$ curl -s localhost:8017/reviewReports/1
{"id":"reviewReports/1","messageId":"chatRooms/1/messages/abcd","reason":"spam"}

$ curl -s -i localhost:8017/chatRooms/1/messages/abcd
HTTP/1.1 404 Not Found

chatRooms/1/messages/abcd not found
```

識別子の末尾が `abcd` から `1` に変わりました。
`reviewReports/1` の `messageId` は消えた Message を指したままで、辿ると 404 です。
2 つ目のリクエストの直後に利用者側が止まれば、Message は両方の ChatRoom に残ります。

### 4-3. 使う場合（差分）
型と保存場所はそのままで、移動の処理をサーバー側に持たせます。
差分の中心は `moveMessage` と、それを呼ぶハンドラです。

```diff go
+func (s *store) moveMessage(srcID, dstID string) (Message, error) {
+	s.mu.Lock()
+	defer s.mu.Unlock() // ①
+	m, ok := s.messages[srcID]
+	if !ok {
+		return Message{}, fail(http.StatusNotFound, srcID+" not found")
+	}
+	if !messageIDPattern.MatchString(dstID) {
+		return Message{}, fail(http.StatusBadRequest, "destinationId must be chatRooms/*/messages/*")
+	}
+	if lastSegment(dstID) != lastSegment(srcID) { // ②
+		return Message{}, fail(http.StatusBadRequest, "only the parent part of the id can change")
+	}
+	dstRoom, ok := s.rooms[parentOf(dstID)]
+	if !ok {
+		return Message{}, fail(http.StatusNotFound, parentOf(dstID)+" not found")
+	}
+	if _, exists := s.messages[dstID]; exists {
+		return Message{}, fail(http.StatusConflict, dstID+" already exists")
+	}
+	if utf8.RuneCountInString(m.Content) > dstRoom.MessageLengthLimit { // ③
+		return Message{}, fail(http.StatusBadRequest, "content exceeds messageLengthLimit of "+dstRoom.ID)
+	}
+	delete(s.messages, srcID)
+	m.ID = dstID
+	s.messages[dstID] = m
+	for id, r := range s.reports { // ④
+		if r.MessageID == srcID {
+			r.MessageID = dstID
+			s.reports[id] = r
+		}
+	}
+	return m, nil
+}
+
 func main() {
 	s := seed()
 	mux := http.NewServeMux()
 
+	mux.HandleFunc("POST /chatRooms/{room}/messages/{msgAndVerb}", func(w http.ResponseWriter, req *http.Request) {
+		msg, verb := splitVerb(req.PathValue("msgAndVerb")) // ⑤
+		if verb != "move" {
+			http.Error(w, "unknown custom method", http.StatusNotFound)
+			return
+		}
+		var in MoveMessageRequest
+		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
+			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
+			return
+		}
+		src := "chatRooms/" + req.PathValue("room") + "/messages/" + msg
+		moved, err := s.moveMessage(src, in.DestinationID)
+		if err != nil {
+			writeError(w, err)
+			return
+		}
+		writeJSON(w, http.StatusOK, moved)
+	})
```

- ① 検証から書き換えまでを 1 つのロックの中で行います。途中の `return` では何も書き換えていないので、失敗しても元のままです
- ② この API はサーバーが識別子を決めるので、move で変えられるのは親の部分だけです
- ③ 移動先の ChatRoom から継承する制約に合わなければ拒否します。切り詰めはしません
- ④ 移動した Message を指している参照を、すべて新しい識別子に書き換えます
- ⑤ `abcd:move` を `:` で分けて、識別子とメソッド名に戻します

:::message
Go 1.22 の `ServeMux` は、パスの一区切りの途中に `:move` のような固定文字列を書けません。
そこで `{msgAndVerb}` で `abcd:move` ごと受け取り、`splitVerb` で分けています。
:::

copy の `copyChatRoom` は、ChatRoom を新しい識別子で複製したあと、`chatRooms/1/messages/` で始まる Message を新しい親の下に複製します。
MessageReviewReport は複製しません。
全文は畳んでおきます。

:::details after/main.go の全文
```go
package main

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"unicode/utf8"
)

type ChatRoom struct {
	ID                 string `json:"id"`
	Title              string `json:"title"`
	MessageLengthLimit int    `json:"messageLengthLimit"`
}

type Message struct {
	ID      string `json:"id"`
	Content string `json:"content"`
}

type MessageReviewReport struct {
	ID        string `json:"id"`
	MessageID string `json:"messageId"`
	Reason    string `json:"reason"`
}

type MoveMessageRequest struct {
	DestinationID string `json:"destinationId"`
}

type apiError struct {
	status int
	msg    string
}

func (e *apiError) Error() string { return e.msg }

func fail(status int, msg string) error { return &apiError{status: status, msg: msg} }

type store struct {
	mu       sync.Mutex
	seq      int
	rooms    map[string]ChatRoom
	messages map[string]Message
	reports  map[string]MessageReviewReport
}

func seed() *store {
	s := &store{rooms: map[string]ChatRoom{}, messages: map[string]Message{}, reports: map[string]MessageReviewReport{}}
	s.rooms["chatRooms/1"] = ChatRoom{ID: "chatRooms/1", Title: "general", MessageLengthLimit: 200}
	s.rooms["chatRooms/2"] = ChatRoom{ID: "chatRooms/2", Title: "random", MessageLengthLimit: 100}
	s.messages["chatRooms/1/messages/abcd"] = Message{ID: "chatRooms/1/messages/abcd", Content: "hello"}
	s.messages["chatRooms/1/messages/efgh"] = Message{ID: "chatRooms/1/messages/efgh", Content: strings.Repeat("x", 140)}
	s.reports["reviewReports/1"] = MessageReviewReport{ID: "reviewReports/1", MessageID: "chatRooms/1/messages/abcd", Reason: "spam"}
	s.seq = 2
	return s
}

var messageIDPattern = regexp.MustCompile(`^chatRooms/[^/]+/messages/[^/]+$`)

func lastSegment(id string) string { return id[strings.LastIndex(id, "/")+1:] }

func parentOf(id string) string { return id[:strings.LastIndex(id, "/messages/")] }

func (s *store) moveMessage(srcID, dstID string) (Message, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	m, ok := s.messages[srcID]
	if !ok {
		return Message{}, fail(http.StatusNotFound, srcID+" not found")
	}
	if !messageIDPattern.MatchString(dstID) {
		return Message{}, fail(http.StatusBadRequest, "destinationId must be chatRooms/*/messages/*")
	}
	if lastSegment(dstID) != lastSegment(srcID) {
		return Message{}, fail(http.StatusBadRequest, "only the parent part of the id can change")
	}
	dstRoom, ok := s.rooms[parentOf(dstID)]
	if !ok {
		return Message{}, fail(http.StatusNotFound, parentOf(dstID)+" not found")
	}
	if _, exists := s.messages[dstID]; exists {
		return Message{}, fail(http.StatusConflict, dstID+" already exists")
	}
	if utf8.RuneCountInString(m.Content) > dstRoom.MessageLengthLimit {
		return Message{}, fail(http.StatusBadRequest, "content exceeds messageLengthLimit of "+dstRoom.ID)
	}
	delete(s.messages, srcID)
	m.ID = dstID
	s.messages[dstID] = m
	for id, r := range s.reports {
		if r.MessageID == srcID {
			r.MessageID = dstID
			s.reports[id] = r
		}
	}
	return m, nil
}

func (s *store) copyChatRoom(srcID string) (ChatRoom, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	room, ok := s.rooms[srcID]
	if !ok {
		return ChatRoom{}, fail(http.StatusNotFound, srcID+" not found")
	}
	s.seq++
	room.ID = "chatRooms/" + strconv.Itoa(s.seq)
	s.rooms[room.ID] = room
	for id, m := range s.messages {
		if strings.HasPrefix(id, srcID+"/messages/") {
			m.ID = room.ID + "/messages/" + lastSegment(id)
			s.messages[m.ID] = m
		}
	}
	return room, nil
}

func (s *store) listMessages(parent string) []Message {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []Message
	for id, m := range s.messages {
		if strings.HasPrefix(id, parent+"/messages/") {
			out = append(out, m)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}

func splitVerb(segment string) (string, string) {
	i := strings.LastIndex(segment, ":")
	if i < 0 {
		return segment, ""
	}
	return segment[:i], segment[i+1:]
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

	mux.HandleFunc("POST /chatRooms/{room}/messages/{msgAndVerb}", func(w http.ResponseWriter, req *http.Request) {
		msg, verb := splitVerb(req.PathValue("msgAndVerb"))
		if verb != "move" {
			http.Error(w, "unknown custom method", http.StatusNotFound)
			return
		}
		var in MoveMessageRequest
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		src := "chatRooms/" + req.PathValue("room") + "/messages/" + msg
		moved, err := s.moveMessage(src, in.DestinationID)
		if err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, moved)
	})

	mux.HandleFunc("POST /chatRooms/{roomAndVerb}", func(w http.ResponseWriter, req *http.Request) {
		room, verb := splitVerb(req.PathValue("roomAndVerb"))
		if verb != "copy" {
			http.Error(w, "unknown custom method", http.StatusNotFound)
			return
		}
		copied, err := s.copyChatRoom("chatRooms/" + room)
		if err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, copied)
	})

	mux.HandleFunc("GET /chatRooms/{room}/messages", func(w http.ResponseWriter, req *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{"results": s.listMessages("chatRooms/" + req.PathValue("room"))})
	})

	mux.HandleFunc("GET /chatRooms/{room}/messages/{msg}", func(w http.ResponseWriter, req *http.Request) {
		id := "chatRooms/" + req.PathValue("room") + "/messages/" + req.PathValue("msg")
		s.mu.Lock()
		m, ok := s.messages[id]
		s.mu.Unlock()
		if !ok {
			http.Error(w, id+" not found", http.StatusNotFound)
			return
		}
		writeJSON(w, http.StatusOK, m)
	})

	mux.HandleFunc("GET /reviewReports/{id}", func(w http.ResponseWriter, req *http.Request) {
		id := "reviewReports/" + req.PathValue("id")
		s.mu.Lock()
		r, ok := s.reports[id]
		s.mu.Unlock()
		if !ok {
			http.Error(w, id+" not found", http.StatusNotFound)
			return
		}
		writeJSON(w, http.StatusOK, r)
	})

	log.Fatal(http.ListenAndServe(":8117", mux))
}
```
:::

### 4-4. 同じ手順で動かすと参照も一緒に移る
同じ移動を 1 リクエストで送ります。

```
$ curl -s -i -X POST 'localhost:8117/chatRooms/1/messages/abcd:move' \
    -d '{"destinationId":"chatRooms/2/messages/abcd"}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"chatRooms/2/messages/abcd","content":"hello"}

$ curl -s localhost:8117/reviewReports/1
{"id":"reviewReports/1","messageId":"chatRooms/2/messages/abcd","reason":"spam"}

$ curl -s -i localhost:8117/chatRooms/1/messages/abcd
HTTP/1.1 404 Not Found

chatRooms/1/messages/abcd not found
```

識別子の末尾 `abcd` はそのままで、`reviewReports/1` の `messageId` は移動先を指しています。
移動先の制約に合わない Message や、末尾を変える移動は拒否され、元の Message は残ります。

```
$ curl -s -i -X POST 'localhost:8117/chatRooms/1/messages/efgh:move' \
    -d '{"destinationId":"chatRooms/2/messages/efgh"}'
HTTP/1.1 400 Bad Request

content exceeds messageLengthLimit of chatRooms/2

$ curl -s localhost:8117/chatRooms/1/messages
{"results":[{"id":"chatRooms/1/messages/efgh","content":"xxxxxxxx...

$ curl -s -i -X POST 'localhost:8117/chatRooms/1/messages/efgh:move' \
    -d '{"destinationId":"chatRooms/2/messages/zzzz"}'
HTTP/1.1 400 Bad Request

only the parent part of the id can change
```

copy は子の Message ごと複製され、Message の識別子の末尾は元と同じになります。

```
$ curl -s -i -X POST 'localhost:8117/chatRooms/1:copy' -d '{}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"chatRooms/3","title":"general","messageLengthLimit":200}

$ curl -s localhost:8117/chatRooms/3/messages
{"results":[{"id":"chatRooms/3/messages/efgh","content":"xxxxxxxx...
```

## 5. 1 リクエストの流れ
本番で `:move` のリクエストがサーバーの中をどう通るかを、順に追います。
送る側を利用者、受ける側をサーバーと呼びます。

1. 利用者が `POST /chatRooms/1/messages/abcd:move` に `{"destinationId": "chatRooms/2/messages/abcd"}` を送る
2. サーバーはパスの最後の区切り `abcd:move` を `:` で分け、メソッド名が `move` であることを確かめる
3. 本文を `MoveMessageRequest` に入れる。読めなければ 400
4. ロックを取る。10 まで他のリクエストは割り込めない
5. 元の Message を探す。無ければ 404
6. `destinationId` の形式と末尾を確かめる。合わなければ 400
7. 移動先の親 ChatRoom を探す。無ければ 404。移動先の識別子が使用済みなら 409
8. Message の長さが移動先の `messageLengthLimit` を超えていれば 400。ここまでの失敗では何も書き換えていない
9. 元を消し、新しい識別子で入れ直し、`messageId` が元を指す MessageReviewReport をすべて書き換える
10. ロックを解放し、移動後の Message を 200 で返す

## 6. 疑問と答え
読みながら引っかかったところです。

**なぜ update で識別子や親を書き換えてはいけないのか**
識別子は変わらないものとして、他のリソースの参照に使われています。
update は 1 つのリソースの中身を変えるメソッドで、参照の書き換えや子リソースの付け替えまでは引き受けません。

**move で識別子の末尾を変えられないのはなぜか**
この API はサーバーが識別子を決めています。
move だけ利用者に決めさせると、create してから move すれば誰でも好きな識別子を付けられてしまいます。
利用者が識別子を指定できる API であれば、名前の変更も move の役目になります。

**copy で MessageReviewReport を複製しないのはなぜか**
複製した Message に同じ報告を付けるべきかは、技術ではなく API の意図で決まることだからです。
書籍の 17.3.3 は、報告側が複数の Message を参照できるようにして、複製を参照リストに足す案を挙げています。

**140 文字の Message を上限 100 文字の ChatRoom に move したらどうなるか**
400 で拒否して、何も変えません。
切り詰めると元に戻せませんし、制約を破ったまま入れると以後の update が通らないリソースになってしまいます。

**子が 1 万件ある ChatRoom を copy している途中で、別の利用者が Message を足したら**
スナップショットかトランザクションの中で読めば、途中の変更は結果に影響しません。
それが無いなら、ロックで書き込みを止めるか、一貫しないコピーを受け入れるか、copy 自体を提供しないかのどれかになります。

**公開 URL で外から参照されている File を move したら 404 になるが、よいのか**
よいです。
API の外の参照の整合性は目標にしません。
インターネット上の参照はもともと保証の無いものだからです。

ここまでを自分の言葉でまとめると、copy と move は「作って消す」の省略形ではなく、識別子・子・参照・制約・途中の失敗をサーバーが引き受ける専用メソッドで、move が要るならまずレイアウトを疑う、です。

## 7. トレードオフ
得られるのは、利用者が 1 リクエストで安全に複製や再配置をできることと、参照が切れないことです。
引き換えに実装は重くなり、処理時間は子リソースの数に比例して伸びます。
一貫性を保つにはスナップショットかトランザクションが要り、それが無いストレージの上では copy を提供しない方がよいと書籍は言っています。

進め方としては、copy は機能として価値があることが多い一方で、move は実装する前にリソースのレイアウトを見直すことが勧められています。
親をまたぐ移動や名前の変更が必要になるのは、識別子の決め方か、参照にすべき関係を親子にしてしまったことが原因であることが多いからです。

## 8. 参考
- 『APIデザイン・パターン』JJ Geewax 著、マイナビ出版、第 17 章
- Amazon S3 の `CopyObject` は、`x-amz-copy-source` でコピー元を指定し、5 GB までのオブジェクトを 1 回のアトミックな操作で複製します。移動専用の API はありません: https://docs.aws.amazon.com/AmazonS3/latest/API/API_CopyObject.html
