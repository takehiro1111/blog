---
title: "[Go]APIデザインパターン 19: 条件に基づく削除（使う/使わないの前後比較）"
emoji: "📘"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Go", "API", "設計", "デザインパターン"]
published: false
---
![](/images/go/go_logo.png =450x)

## 本記事の内容
- 『APIデザイン・パターン』(JJ Geewax 著、マイナビ出版) の第 19 章「条件に基づく削除」を、Go で書き直しながら読んだメモです
- パターンを使わない実装と使う実装を同じ手順で動かして、何が変わるかを出力で確かめます
- コードは Go 1.22 以降の `net/http` と標準ライブラリだけで動きます
- シリーズの目次は「[Go]APIデザインパターン 00: 目次と、パターンを使わないとどうなるか」にあります

## 1. 結論
条件に合うリソースをまとめて消したい時は、`filter` を受け取る `:purge` カスタムメソッドを用意します。
ただし purge は API の中で一番危険なメソッドです。
そこで `force: true` を付けた時だけ本当に消し、付けなければ「何件消えるか」と「消える識別子の見本」だけを返す作りにします。
そもそも本当に必要な時以外は提供しない、というのが書籍の立場です。

## 2. 困る場面
アーカイブ済みの Message を全部消したいとします。
標準メソッドだけなら、`archived: true` で list して識別子を集め、それを batchDelete に渡すことになります。
これは 2 回以上のリクエストになりますし、list と delete の間に状態が変わると、もうアーカイブ済みでない Message を消してしまいます。

それなら `filter` を受け取って 1 回で消す purge を作ればよさそうですが、素朴に作ると別の問題が出ます。
purge の `filter` は list の `filter` と同じ意味にするので、空なら全件に一致します。
利用者がフィールド名を `fliter` と打ち間違えただけで `filter` は空になり、ChatRoom の Message が全部消えます。
4-2 で、実際に全部消えるところを見ます。

## 3. 足すもの
`POST /chatRooms/{room}/messages:purge` に `filter` と `force` を渡し、`purgeCount` と `purgeSample` が返ります。

| `force` | 動作 | `purgeCount` | `purgeSample` |
|---|---|---|---|
| 無し / false | 消さない | 推定でもよい | 消える予定の識別子の見本 |
| true | 消す | 実際に消した件数 | 無し |

`force` を付け忘れた時に安全な方に倒れるように、既定を「消さない」にしてあります。
第 27 章の `validateOnly` と同じ役目のフィールドですが、既定が逆なので名前も変えています。
`validateOnly` を付け忘れると消えてしまうのに対して、`force` を付け忘れてもプレビューが返るだけです。

`filter` の意味は list と同じで、空なら全件に一致します。
空の `filter` を拒否したくなりますが、list と挙動が違うと利用者が混乱するので、代わりに既定を安全にしています。

`purgeCount` は、`force` 無しの時は推定値でも構いません。
ただし少なく見積もるのは避けます。
100 件と言われて実行したら 1,000 件消えた、という事態は利用者にとって最悪だからです。
`purgeSample` は、大きなデータセットなら 100 件以上、小さければ全件を入れます。
件数だけでは「50 件消える」が正しい 50 件かどうか分からないので、見本を抜き打ちで確かめてもらうためです。

プレビューと実行の間にデータが変わらない保証はありません。
変わっていたら失敗させる作りも技術的には可能ですが、書き込みの多いデータセットでは purge がほぼ使えなくなるので、書籍はそれを勧めていません。

Go の型にするとこうなります。

```go
type PurgeMessagesRequest struct {
	Filter string `json:"filter"`
	Force  bool   `json:"force,omitempty"` // ①
}

type PurgeMessagesResponse struct {
	PurgeCount  int      `json:"purgeCount"`
	PurgeSample []string `json:"purgeSample,omitempty"` // ②
}

const purgeSampleSize = 100
```

- ① JSON に無ければ `false` です。`false` なら消しません
- ② `force` が無い時だけ入ります

## 4. 前後比較
### 4-1. 使わない場合
`filter` に合うものをその場で消す purge です。
`matchFilter` は list と共通で、空文字列なら全件に一致します。

```go
func matchFilter(filter string, m Message) (bool, error) {
	switch strings.TrimSpace(filter) {
	case "": // ①
		return true, nil
	case "archived: true":
		return m.Archived, nil
	case "archived: false":
		return !m.Archived, nil
	}
	return false, &apiError{http.StatusBadRequest, "unsupported filter: " + filter}
}

func (s *store) purge(parent, filter string) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	remain := s.messages[:0]
	count := 0
	for _, m := range s.messages {
		ok, err := matchFilter(filter, m)
		if err != nil {
			return 0, err
		}
		if ok && strings.HasPrefix(m.ID, parent+"/messages/") {
			count++ // ②
			continue
		}
		remain = append(remain, m)
	}
	s.messages = remain
	return count, nil
}

mux.HandleFunc("POST /chatRooms/{room}/messages:purge", func(w http.ResponseWriter, req *http.Request) {
	var in PurgeMessagesRequest
	if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
		http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
		return
	}
	count, err := s.purge("chatRooms/"+req.PathValue("room"), in.Filter)
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, PurgeMessagesResponse{PurgeCount: count})
})
```

- ① フィルター無しは list と同じく全件です
- ② 条件に合ったものを、確認無しでその場で消します

:::message
`remain := s.messages[:0]` は、元のスライスと同じメモリを使う長さ 0 のスライスです。
残すものだけ `append` していくと、新しい配列を作らずに絞り込めます。
:::

### 4-2. 動かすと打ち間違いで全件消える
起動時に Message が 5 件あり、うち 2 件がアーカイブ済みです。
`filter` を `fliter` と打ち間違えて送ります。

```
$ curl -s 'localhost:8019/chatRooms/1/messages?filter=archived:%20true'
{"results":[{"id":"chatRooms/1/messages/1","content":"hello","archived":true},{"id":"chatRooms/1/messages/3","content":"old news","archived":true}]}

$ curl -s -i -X POST localhost:8019/chatRooms/1/messages:purge \
    -d '{"fliter":"archived: true"}'
HTTP/1.1 200 OK
Content-Type: application/json

{"purgeCount":5}

$ curl -s localhost:8019/chatRooms/1/messages
{"results":[]}
```

消したかったのは 2 件ですが、5 件すべてが消えました。
JSON の `fliter` は無視され、`filter` は空文字列として扱われたからです。
エラーにもならないので、気付くのはデータが無くなった後です。

### 4-3. 使う場合（差分）
リクエストに `force`、レスポンスに `purgeSample` を足し、`force` が無ければ消さずに見本を返すようにします。

```diff go
 type PurgeMessagesRequest struct {
 	Filter string `json:"filter"`
+	Force  bool   `json:"force,omitempty"`
 }
 
 type PurgeMessagesResponse struct {
-	PurgeCount int `json:"purgeCount"`
+	PurgeCount  int      `json:"purgeCount"`
+	PurgeSample []string `json:"purgeSample,omitempty"`
 }
 
-func (s *store) purge(parent, filter string) (int, error) {
+func (s *store) purge(parent, filter string, force bool) (PurgeMessagesResponse, error) {
 	s.mu.Lock()
 	defer s.mu.Unlock()
+	var matched []string
 	remain := s.messages[:0]
-	count := 0
 	for _, m := range s.messages {
 		ok, err := matchFilter(filter, m)
 		if err != nil {
-			return 0, err
+			return PurgeMessagesResponse{}, err
 		}
 		if ok && strings.HasPrefix(m.ID, parent+"/messages/") {
-			count++
-			continue
+			matched = append(matched, m.ID)
+			if force { // ①
+				continue
+			}
 		}
 		remain = append(remain, m)
 	}
 	s.messages = remain
-	return count, nil
+	resp := PurgeMessagesResponse{PurgeCount: len(matched)}
+	if !force { // ②
+		if len(matched) > purgeSampleSize {
+			matched = matched[:purgeSampleSize]
+		}
+		resp.PurgeSample = matched
+	}
+	return resp, nil
 }
```

- ① `force` の時だけ `remain` から外します。それ以外は条件に合っても残します
- ② 消さなかった時は、件数と一緒に見本を返します。この実装では全件を数えているので件数は正確ですが、大きなデータセットでは推定値でも構いません

:::message
`matched[:purgeSampleSize]` は、スライスの先頭から 100 件だけを切り出す書き方です。
Go のスライスは配列の一部を指す「窓」なので、切り出してもコピーは発生しません。
:::

全文は畳んでおきます。

:::details after/main.go の全文
```go
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"sync"
)

type Message struct {
	ID       string `json:"id"`
	Content  string `json:"content"`
	Archived bool   `json:"archived"`
}

type PurgeMessagesRequest struct {
	Filter string `json:"filter"`
	Force  bool   `json:"force,omitempty"`
}

type PurgeMessagesResponse struct {
	PurgeCount  int      `json:"purgeCount"`
	PurgeSample []string `json:"purgeSample,omitempty"`
}

const purgeSampleSize = 100

type store struct {
	mu       sync.Mutex
	messages []Message
}

func seed() *store {
	return &store{messages: []Message{
		{ID: "chatRooms/1/messages/1", Content: "hello", Archived: true},
		{ID: "chatRooms/1/messages/2", Content: "hi", Archived: false},
		{ID: "chatRooms/1/messages/3", Content: "old news", Archived: true},
		{ID: "chatRooms/1/messages/4", Content: "lunch?", Archived: false},
		{ID: "chatRooms/1/messages/5", Content: "see you", Archived: false},
	}}
}

func matchFilter(filter string, m Message) (bool, error) {
	switch strings.TrimSpace(filter) {
	case "":
		return true, nil
	case "archived: true":
		return m.Archived, nil
	case "archived: false":
		return !m.Archived, nil
	}
	return false, &apiError{http.StatusBadRequest, "unsupported filter: " + filter}
}

type apiError struct {
	status int
	msg    string
}

func (e *apiError) Error() string { return e.msg }

func (s *store) purge(parent, filter string, force bool) (PurgeMessagesResponse, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var matched []string
	remain := s.messages[:0]
	for _, m := range s.messages {
		ok, err := matchFilter(filter, m)
		if err != nil {
			return PurgeMessagesResponse{}, err
		}
		if ok && strings.HasPrefix(m.ID, parent+"/messages/") {
			matched = append(matched, m.ID)
			if force {
				continue
			}
		}
		remain = append(remain, m)
	}
	s.messages = remain
	resp := PurgeMessagesResponse{PurgeCount: len(matched)}
	if !force {
		if len(matched) > purgeSampleSize {
			matched = matched[:purgeSampleSize]
		}
		resp.PurgeSample = matched
	}
	return resp, nil
}

func (s *store) list(parent, filter string) ([]Message, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []Message{}
	for _, m := range s.messages {
		ok, err := matchFilter(filter, m)
		if err != nil {
			return nil, err
		}
		if ok && strings.HasPrefix(m.ID, parent+"/messages/") {
			out = append(out, m)
		}
	}
	return out, nil
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, err error) {
	if ae, ok := err.(*apiError); ok {
		http.Error(w, ae.msg, ae.status)
		return
	}
	http.Error(w, err.Error(), http.StatusInternalServerError)
}

func main() {
	s := seed()
	mux := http.NewServeMux()

	mux.HandleFunc("POST /chatRooms/{room}/messages:purge", func(w http.ResponseWriter, req *http.Request) {
		var in PurgeMessagesRequest
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		resp, err := s.purge("chatRooms/"+req.PathValue("room"), in.Filter, in.Force)
		if err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, resp)
	})

	mux.HandleFunc("GET /chatRooms/{room}/messages", func(w http.ResponseWriter, req *http.Request) {
		results, err := s.list("chatRooms/"+req.PathValue("room"), req.URL.Query().Get("filter"))
		if err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"results": results})
	})

	log.Fatal(http.ListenAndServe(":8119", mux))
}
```
:::

### 4-4. 同じ手順で動かすと見本が返るだけで消えない
4-2 と同じ打ち間違いのリクエストを送ります。

```
$ curl -s -i -X POST localhost:8119/chatRooms/1/messages:purge \
    -d '{"fliter":"archived: true"}'
HTTP/1.1 200 OK
Content-Type: application/json

{"purgeCount":5,"purgeSample":["chatRooms/1/messages/1","chatRooms/1/messages/2","chatRooms/1/messages/3","chatRooms/1/messages/4","chatRooms/1/messages/5"]}

$ curl -s localhost:8119/chatRooms/1/messages
{"results":[{"id":"chatRooms/1/messages/1","content":"hello","archived":true},{"id":"chatRooms/1/messages/2","content":"hi","archived":false}, ...
```

何も消えていません。
`purgeCount` が 5 で、`purgeSample` に `archived: false` の Message も混ざっているので、ここで条件がおかしいと気付けます。
`filter` を直すと見本が 2 件になり、`force: true` を付けた時だけ消えます。

```
$ curl -s -i -X POST localhost:8119/chatRooms/1/messages:purge \
    -d '{"filter":"archived: true"}'
HTTP/1.1 200 OK
Content-Type: application/json

{"purgeCount":2,"purgeSample":["chatRooms/1/messages/1","chatRooms/1/messages/3"]}

$ curl -s -i -X POST localhost:8119/chatRooms/1/messages:purge \
    -d '{"filter":"archived: true","force":true}'
HTTP/1.1 200 OK
Content-Type: application/json

{"purgeCount":2}

$ curl -s localhost:8119/chatRooms/1/messages
{"results":[{"id":"chatRooms/1/messages/2","content":"hi","archived":false},{"id":"chatRooms/1/messages/4","content":"lunch?","archived":false},{"id":"chatRooms/1/messages/5","content":"see you","archived":false}]}
```

`filter` の中身の打ち間違い（`archvied: true`）は、list と同じく 400 Bad Request です。
危ないのはフィールド名ごと間違えて `filter` が空になる方で、`force` の既定値がそこを守っています。

## 5. 1 リクエストの流れ
本番で `:purge` のリクエストがサーバーの中をどう通るかを、順に追います。
送る側を利用者、受ける側をサーバーと呼びます。

1. 利用者が `POST /chatRooms/1/messages:purge` に `{"filter": "archived: true"}` を送る。`force` は付けない
2. サーバーは本文を `PurgeMessagesRequest` に入れる。読めなければ 400。`force` は `false` になる
3. ロックを取る
4. Message を順に見て、`filter` に合うものの識別子を `matched` に集める。`filter` が解釈できなければ 400。`force` が `false` なので何も消さない
5. ロックを解放し、`purgeCount` に件数、`purgeSample` に識別子（100 件まで）を入れて 200 で返す
6. 利用者は `purgeSample` を見て条件が正しいか確かめ、同じ `filter` に `force: true` を付けて送り直す
7. サーバーは 3 と 4 を繰り返し、今度は合ったものを `remain` から外す。`purgeCount` だけを 200 で返す

## 6. 疑問と答え
読みながら引っかかったところです。

**空の `filter` を拒否してしまえばよいのでは**
list の `filter` は空なら全件を返すので、purge だけ違う挙動にすると「フィルターはメソッドによって意味が変わる」と利用者が思い始めます。
それを避けるために、空を許したうえで既定を「消さない」にしています。

**`validateOnly: true` でプレビューにする設計と何が違うのか**
やることは同じで、既定値が逆です。
`validateOnly` は付け忘れると実行されてしまいます。
purge のように間違いの代償が大きいメソッドでは、付け忘れた時に安全な方へ倒れる `force` の形にします。

**`purgeCount` が推定でよいのはなぜか**
プレビューのために全件を正確に数えると、消しもしないデータに計算を使うことになるからです。
ただし少なく見積もってはいけません。
実行して初めて 10 倍消えた、となると、プレビューの意味がありません。

**プレビューと実行の間にデータが変わったら**
変わりうる、というのが答えです。
変わっていたら失敗させることもできますが、書き込みが多いデータセットでは毎回失敗して使い物になりません。
プレビューは条件の間違いを見つけるための道具であって、消える集合を固定するものではありません。

**論理削除（第 25 章）をサポートしているリソースに purge を送ったら**
書籍はこれを練習問題にしていて、答えを書いていません。
私は、標準の delete が論理削除なら purge も論理削除に揃える方が、利用者にとって予測しやすいと考えています。

ここまでを自分の言葉でまとめると、purge は list と batchDelete を 1 回にまとめた危険なメソッドで、`force` を付けない限り「何が何件消えるか」を返すだけ、です。

## 7. トレードオフ
得られるのは、識別子を集める往復無しに、条件に合うものを 1 回で消せることです。
引き換えに、利用者は消える全容を見ないままデータを消せてしまいます。
`force` の既定値と `purgeSample` で守ってはいますが、大量のデータを誤って消す可能性は残ります。

そのため書籍は、どうしても必要な場合を除いてこのメソッドを提供しないことを勧めています。
提供するなら、プレビューを既定にし、件数と見本を必ず返す、という形を崩さないことになります。

## 8. 参考
- 『APIデザイン・パターン』JJ Geewax 著、マイナビ出版、第 19 章
- https://google.aip.dev/165 （Criteria-based delete）
