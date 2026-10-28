---
title: "[Go]APIデザインパターン 22: フィルタリング（使う/使わないの前後比較）"
emoji: "📘"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Go", "API", "設計", "デザインパターン"]
published: false
---
![](/images/go/go_logo.png =450x)

## 本記事の内容
- 『APIデザイン・パターン』(JJ Geewax 著、マイナビ出版) の第 22 章「フィルタリング」を、Go で書き直しながら読んだメモです
- パターンを使わない実装と使う実装を同じ手順で動かして、何が変わるかを出力で確かめます
- コードは Go 1.22 以降の `net/http` と標準ライブラリだけで動きます
- シリーズの目次は「[Go]APIデザインパターン 00: 目次と、パターンを使わないとどうなるか」にあります

## 1. 結論
一覧を返すメソッドのリクエストに、`filter` という文字列のフィールドを 1 つ足します。
`title = "New Chat!" AND userLimit >= 5` のような条件を文字列のまま受け取り、サーバー側で解釈して、合うリソースだけを返します。
構文の決まりはサーバーが持つので、書ける条件を増やす時も利用者のコードを変えずに済みます。
利用者が全件を取り寄せて自分で絞り込む必要はなくなります。

件数が数十件で止まる一覧には要りません。

## 2. 困る場面
一覧の中から条件に合うものだけが欲しい、という要求は get と list の中間にあります。
list しか無ければ、利用者は全ページを取り寄せて自分のコードで絞り込むしかありません。
該当が 1 件も無い時でも、無いことを知るために全件を転送することになります。

では条件ごとにクエリパラメータを足せばよいかというと、そうもいきませんでした。
`title=` と `userLimit=` を足した時点で表せるのは、等しいかどうかの AND だけです。
「A または B」や「5 以上」が書けず、条件が増えるたびにパラメータの組み合わせが膨らみます。
4-2 で、OR が書けないところと、フィールド名のタイポが黙って無視されるところを見ます。

## 3. 足すもの
`ListChatRoomsRequest` に `filter`（string）を足すだけです。
ページ分割の `maxPageSize` と `pageToken` と並べて持ちます。
フィールドは 1 つでも、どう解釈するかの決まりがこの章の中身でした。

構文は SQL の WHERE 句に近い比較式で、AND と OR と括弧で組み合わせます。
書籍は特定の構文を決めておらず、CEL や Google の AIP-160 を例に挙げて、一から自分で作らないよう勧めています。

評価の入力は、フィルターの文字列と、判定するリソース 1 件だけにします。
`admin.name = "Luca"` のように `admin` が別リソースの識別子を指している場合は受け付けず、`settings.visibility` のようにリソースの中に埋め込まれた値だけを見ます。
外部に問い合わせに行かないことで、実行時間が無制限に伸びるのを防いでいます。

配列は位置ではなく、値を含むかどうかで判定します。
`tags[0] = "new"` は受け付けず、`tags:"new"` と書きます。

構文は厳密にします。
存在しないフィールド名や、数値のフィールドに文字列を比べる式は、黙って空の結果を返すのではなく、位置を添えて 400 Bad Request にします。

基本の比較で足りない時は、`endsWith(title, "Chat!")` のような関数を用意します。
ワイルドカードを構文に足すとエスケープの問題を持ち込むので、関数で逃がす方が安全です。

記法をまとめるとこうなります。

| 記法 | 意味 |
|---|---|
| `title = "New Chat!"` | 文字列が等しい（`!=` も） |
| `userLimit >= 5` | 数値の比較（`<` `<=` `>` `>=` `!=` も） |
| `tags:"public"` | 配列が値を含む |
| `settings.visibility = "public"` | 埋め込まれたオブジェクトの中のフィールド |
| `A AND B` `A OR B` `( )` | 組み合わせ。AND が先に結合する |
| `endsWith(title, "Chat!")` | 関数 |

Go では、文字列を字句に分ける `token` と、リソース 1 件を相手に式を評価する `evaluator` を用意しました。

```go
type token struct {
	kind string // ident, string, number, op, lparen, rparen, comma, eof
	text string
	pos  int // ①
}

type evaluator struct {
	toks []token
	pos  int
	res  map[string]any // ②
}
```

- ① 元の文字列の中の位置です。エラーに「position 12」と添えるために持ちます
- ② 判定するリソース 1 件です。`ChatRoom` を一度 JSON にして `map` に戻し、JSON のキー名でフィールドを引けるようにしています

## 4. 前後比較
### 4-1. 使わない場合
条件ごとにクエリパラメータを読む形です。

```go
	mux.HandleFunc("GET /chatRooms", func(w http.ResponseWriter, req *http.Request) {
		q := req.URL.Query()
		title := q.Get("title")         // ①
		userLimit := q.Get("userLimit") // ①
		results := []ChatRoom{}
		for _, r := range s.all() {
			if title != "" && r.Title != title { // ②
				continue
			}
			if userLimit != "" && strconv.Itoa(r.UserLimit) != userLimit {
				continue
			}
			results = append(results, r)
		}
		writeJSON(w, http.StatusOK, ListChatRoomsResponse{Results: results})
	})
```

- ① 条件が 1 つ増えるたびに、パラメータと `if` が 1 組ずつ増えます
- ② 書けるのは「等しい」の AND だけです

### 4-2. 動かすと OR が書けず、タイポは無視される
4 件の部屋を入れてあります。
`title` が 1 つなら絞れます。

```
$ curl -s -G localhost:8022/chatRooms --data-urlencode 'title=New Chat!'
{"results":[{"id":"1","title":"New Chat!","userLimit":10,"tags":["new","public"],"admin":"users/1","settings":{"visibility":"public"}},{"id":"3","title":"New Chat!","userLimit":2,"tags":["new"],"admin":"users/2","settings":{"visibility":"private"}}]}
```

「New Chat! または Old Chat!」のつもりで 2 つ渡すと、2 つ目は黙って捨てられます。
フィールド名を `ttile` と打ち間違えると、エラーではなく全件が返ります。
`userLimit=5` は「5 に等しい」にしかならず、5 以上は表せません。

```
$ curl -s -G localhost:8022/chatRooms --data-urlencode 'title=New Chat!' \
    --data-urlencode 'title=Old Chat!'
{"results":[{"id":"1","title":"New Chat!","userLimit":10,"tags":["new","public"],"admin":"users/1","settings":{"visibility":"public"}},{"id":"3","title":"New Chat!","userLimit":2,"tags":["new"],"admin":"users/2","settings":{"visibility":"private"}}]}

$ curl -s -G localhost:8022/chatRooms --data-urlencode 'ttile=New Chat!'
{"results":[{"id":"1","title":"New Chat!","userLimit":10,"tags":["new","public"],"admin":"users/1","settings":{"visibility":"public"}},{"id":"2","title":"Old Chat!","userLimit":3,"tags":["old"],"admin":"users/2","settings":{"visibility":"private"}},{"id":"3","title":"New Chat!","userLimit":2,"tags":["new"],"admin":"users/2","settings":{"visibility":"private"}},{"id":"4","title":"Team Chat","userLimit":50,"tags":["public"],"admin":"users/1","settings":{"visibility":"public"}}]}

$ curl -s -G localhost:8022/chatRooms --data-urlencode 'userLimit=5'
{"results":[]}
```

:::message
`q.Get("title")` は同じ名前のパラメータが複数あっても最初の 1 つしか返しません。
全部欲しい時は `q["title"]` でスライスとして取り出します。
:::

### 4-3. 使う場合（差分）
ハンドラは `filter` を 1 つ読んで、1 件ずつ `matches` に渡すだけになります。

```diff go
 	mux.HandleFunc("GET /chatRooms", func(w http.ResponseWriter, req *http.Request) {
-		q := req.URL.Query()
-		title := q.Get("title")
-		userLimit := q.Get("userLimit")
+		filter := req.URL.Query().Get("filter")
 		results := []ChatRoom{}
 		for _, r := range s.all() {
-			if title != "" && r.Title != title {
-				continue
-			}
-			if userLimit != "" && strconv.Itoa(r.UserLimit) != userLimit {
-				continue
-			}
-			results = append(results, r)
+			ok := true
+			if filter != "" {
+				var err error
+				ok, err = matches(filter, r) // ①
+				if err != nil {
+					http.Error(w, "invalid filter: "+err.Error(), http.StatusBadRequest)
+					return
+				}
+			}
+			if ok {
+				results = append(results, r)
+			}
 		}
 		writeJSON(w, http.StatusOK, ListChatRoomsResponse{Results: results})
 	})
```

- ① 構文や型の誤りは `err` で返ってくるので、その場で 400 Bad Request にします。この例では 1 件ごとに構文解析していますが、本番では 1 回だけ解析して使い回します

決まりごとが集まっているのは、フィールドを引く `lookup` と、値を比べる `compare` です。

```go
func (e *evaluator) lookup(t token) (any, error) { // ①
	var cur any = e.res
	for _, part := range strings.Split(t.text, ".") {
		m, ok := cur.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("invalid field %q at position %d", t.text, t.pos)
		}
		cur, ok = m[part]
		if !ok {
			return nil, fmt.Errorf("invalid field %q at position %d", t.text, t.pos)
		}
	}
	return cur, nil
}

func compare(field any, op token, val token) (bool, error) {
	switch f := field.(type) {
	case string:
		if val.kind != "string" || (op.text != "=" && op.text != "!=") {
			return false, fmt.Errorf("field is a string; cannot apply %s %s at position %d", op.text, val.text, op.pos)
		}
		return (f == val.text) == (op.text == "="), nil
	case float64: // ②
		if val.kind != "number" {
			return false, fmt.Errorf("field is a number; cannot compare with %q at position %d", val.text, val.pos)
		}
		n, _ := strconv.ParseFloat(val.text, 64)
		switch op.text {
		case "=":
			return f == n, nil
		case "!=":
			return f != n, nil
		case "<":
			return f < n, nil
		case "<=":
			return f <= n, nil
		case ">":
			return f > n, nil
		case ">=":
			return f >= n, nil
		}
	case []any: // ③
		if op.text != ":" || val.kind != "string" {
			return false, fmt.Errorf("field is an array; use field:\"value\" at position %d", op.pos)
		}
		for _, item := range f {
			if item == val.text {
				return true, nil
			}
		}
		return false, nil
	}
	return false, fmt.Errorf("cannot apply %s to this field at position %d", op.text, op.pos)
}
```

- ① `settings.visibility` は `.` で区切って `map` を辿ります。途中で `map` でない値に当たる（`admin` は文字列）か、キーが無ければエラーです
- ② 文字列と数値を黙って変換して比べることはせず、型が合わなければエラーにします
- ③ 配列は含むかどうかだけで、`tags = "new"` のような等号は断ります

:::message
`json.Unmarshal` で `map[string]any` に入れた JSON の数値は、整数でも `float64` になります。
`switch f := field.(type)` の `case float64` はそのためで、`case int` と書いても一致しません。
:::

字句解析と `AND` / `OR` / 括弧の処理を含めた全文は畳んでおきます。

:::details after/main.go の全文
```go
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"unicode"
)

type Settings struct {
	Visibility string `json:"visibility"`
}

type ChatRoom struct {
	ID        string   `json:"id"`
	Title     string   `json:"title"`
	UserLimit int      `json:"userLimit"`
	Tags      []string `json:"tags"`
	Admin     string   `json:"admin"`
	Settings  Settings `json:"settings"`
}

type ListChatRoomsResponse struct {
	Results []ChatRoom `json:"results"`
}

type store struct {
	mu    sync.Mutex
	rooms []ChatRoom
}

func (s *store) all() []ChatRoom {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]ChatRoom{}, s.rooms...)
}

// ---- filter: tokenizer ----

type token struct {
	kind string // ident, string, number, op, lparen, rparen, comma, eof
	text string
	pos  int
}

func tokenize(src string) ([]token, error) {
	var out []token
	i := 0
	for i < len(src) {
		c := src[i]
		switch {
		case c == ' ':
			i++
		case c == '(':
			out = append(out, token{"lparen", "(", i})
			i++
		case c == ')':
			out = append(out, token{"rparen", ")", i})
			i++
		case c == ',':
			out = append(out, token{"comma", ",", i})
			i++
		case c == '"':
			j := i + 1
			for j < len(src) && src[j] != '"' {
				j++
			}
			if j >= len(src) {
				return nil, fmt.Errorf("unterminated string at position %d", i)
			}
			out = append(out, token{"string", src[i+1 : j], i})
			i = j + 1
		case strings.ContainsRune("=!<>:", rune(c)):
			j := i + 1
			if j < len(src) && src[j] == '=' {
				j++
			}
			out = append(out, token{"op", src[i:j], i})
			i = j
		case unicode.IsDigit(rune(c)):
			j := i
			for j < len(src) && unicode.IsDigit(rune(src[j])) {
				j++
			}
			out = append(out, token{"number", src[i:j], i})
			i = j
		case unicode.IsLetter(rune(c)) || c == '_':
			j := i
			for j < len(src) && (unicode.IsLetter(rune(src[j])) || unicode.IsDigit(rune(src[j])) || src[j] == '_' || src[j] == '.') {
				j++
			}
			out = append(out, token{"ident", src[i:j], i})
			i = j
		default:
			return nil, fmt.Errorf("unexpected character %q at position %d", c, i)
		}
	}
	return append(out, token{"eof", "", len(src)}), nil
}

// ---- filter: parser + evaluator (単一リソースだけを入力にする) ----

type evaluator struct {
	toks []token
	pos  int
	res  map[string]any
}

func (e *evaluator) peek() token { return e.toks[e.pos] }
func (e *evaluator) next() token { t := e.toks[e.pos]; e.pos++; return t }

func (e *evaluator) expr() (bool, error) { // OR
	left, err := e.term()
	if err != nil {
		return false, err
	}
	for e.peek().kind == "ident" && e.peek().text == "OR" {
		e.next()
		right, err := e.term()
		if err != nil {
			return false, err
		}
		left = left || right
	}
	return left, nil
}

func (e *evaluator) term() (bool, error) { // AND
	left, err := e.factor()
	if err != nil {
		return false, err
	}
	for e.peek().kind == "ident" && e.peek().text == "AND" {
		e.next()
		right, err := e.factor()
		if err != nil {
			return false, err
		}
		left = left && right
	}
	return left, nil
}

func (e *evaluator) factor() (bool, error) {
	t := e.next()
	if t.kind == "lparen" {
		v, err := e.expr()
		if err != nil {
			return false, err
		}
		if e.next().kind != "rparen" {
			return false, fmt.Errorf("expected ) at position %d", t.pos)
		}
		return v, nil
	}
	if t.kind != "ident" {
		return false, fmt.Errorf("expected field name at position %d", t.pos)
	}
	if e.peek().kind == "lparen" {
		return e.function(t)
	}
	op := e.next()
	if op.kind != "op" {
		return false, fmt.Errorf("expected operator at position %d", op.pos)
	}
	val := e.next()
	field, err := e.lookup(t)
	if err != nil {
		return false, err
	}
	return compare(field, op, val)
}

func (e *evaluator) function(name token) (bool, error) {
	e.next() // (
	field := e.next()
	if e.next().kind != "comma" {
		return false, fmt.Errorf("expected , at position %d", field.pos)
	}
	arg := e.next()
	if e.next().kind != "rparen" {
		return false, fmt.Errorf("expected ) at position %d", arg.pos)
	}
	v, err := e.lookup(field)
	if err != nil {
		return false, err
	}
	s, ok := v.(string)
	if name.text != "endsWith" || !ok || arg.kind != "string" {
		return false, fmt.Errorf("unknown function %q at position %d", name.text, name.pos)
	}
	return strings.HasSuffix(s, arg.text), nil
}

func (e *evaluator) lookup(t token) (any, error) {
	var cur any = e.res
	for _, part := range strings.Split(t.text, ".") {
		m, ok := cur.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("invalid field %q at position %d", t.text, t.pos)
		}
		cur, ok = m[part]
		if !ok {
			return nil, fmt.Errorf("invalid field %q at position %d", t.text, t.pos)
		}
	}
	return cur, nil
}

func compare(field any, op token, val token) (bool, error) {
	switch f := field.(type) {
	case string:
		if val.kind != "string" || (op.text != "=" && op.text != "!=") {
			return false, fmt.Errorf("field is a string; cannot apply %s %s at position %d", op.text, val.text, op.pos)
		}
		return (f == val.text) == (op.text == "="), nil
	case float64:
		if val.kind != "number" {
			return false, fmt.Errorf("field is a number; cannot compare with %q at position %d", val.text, val.pos)
		}
		n, _ := strconv.ParseFloat(val.text, 64)
		switch op.text {
		case "=":
			return f == n, nil
		case "!=":
			return f != n, nil
		case "<":
			return f < n, nil
		case "<=":
			return f <= n, nil
		case ">":
			return f > n, nil
		case ">=":
			return f >= n, nil
		}
	case []any:
		if op.text != ":" || val.kind != "string" {
			return false, fmt.Errorf("field is an array; use field:\"value\" at position %d", op.pos)
		}
		for _, item := range f {
			if item == val.text {
				return true, nil
			}
		}
		return false, nil
	}
	return false, fmt.Errorf("cannot apply %s to this field at position %d", op.text, op.pos)
}

func matches(filter string, r ChatRoom) (bool, error) {
	toks, err := tokenize(filter)
	if err != nil {
		return false, err
	}
	b, _ := json.Marshal(r)
	var m map[string]any
	json.Unmarshal(b, &m)
	e := &evaluator{toks: toks, res: m}
	v, err := e.expr()
	if err != nil {
		return false, err
	}
	if e.peek().kind != "eof" {
		return false, fmt.Errorf("unexpected %q at position %d", e.peek().text, e.peek().pos)
	}
	return v, nil
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func seed() []ChatRoom {
	return []ChatRoom{
		{ID: "1", Title: "New Chat!", UserLimit: 10, Tags: []string{"new", "public"}, Admin: "users/1", Settings: Settings{Visibility: "public"}},
		{ID: "2", Title: "Old Chat!", UserLimit: 3, Tags: []string{"old"}, Admin: "users/2", Settings: Settings{Visibility: "private"}},
		{ID: "3", Title: "New Chat!", UserLimit: 2, Tags: []string{"new"}, Admin: "users/2", Settings: Settings{Visibility: "private"}},
		{ID: "4", Title: "Team Chat", UserLimit: 50, Tags: []string{"public"}, Admin: "users/1", Settings: Settings{Visibility: "public"}},
	}
}

func main() {
	s := &store{rooms: seed()}
	mux := http.NewServeMux()

	mux.HandleFunc("GET /chatRooms", func(w http.ResponseWriter, req *http.Request) {
		filter := req.URL.Query().Get("filter")
		results := []ChatRoom{}
		for _, r := range s.all() {
			ok := true
			if filter != "" {
				var err error
				ok, err = matches(filter, r)
				if err != nil {
					http.Error(w, "invalid filter: "+err.Error(), http.StatusBadRequest)
					return
				}
			}
			if ok {
				results = append(results, r)
			}
		}
		writeJSON(w, http.StatusOK, ListChatRoomsResponse{Results: results})
	})

	log.Fatal(http.ListenAndServe(":8122", mux))
}
```
:::

### 4-4. 同じ手順で動かすと OR も書け、間違いは 400 になる
OR と括弧、数値の比較、配列、埋め込まれたフィールド、関数の順に試します。

```
$ curl -s -G localhost:8122/chatRooms \
    --data-urlencode 'filter=title = "New Chat!" OR title = "Old Chat!"'
{"results":[{"id":"1","title":"New Chat!","userLimit":10,"tags":["new","public"],"admin":"users/1","settings":{"visibility":"public"}},{"id":"2","title":"Old Chat!","userLimit":3,"tags":["old"],"admin":"users/2","settings":{"visibility":"private"}},{"id":"3","title":"New Chat!","userLimit":2,"tags":["new"],"admin":"users/2","settings":{"visibility":"private"}}]}

$ curl -s -G localhost:8122/chatRooms \
    --data-urlencode 'filter=(title = "New Chat!" AND userLimit >= 5) OR title = "Old Chat!"'
{"results":[{"id":"1","title":"New Chat!","userLimit":10,"tags":["new","public"],"admin":"users/1","settings":{"visibility":"public"}},{"id":"2","title":"Old Chat!","userLimit":3,"tags":["old"],"admin":"users/2","settings":{"visibility":"private"}}]}

$ curl -s -G localhost:8122/chatRooms \
    --data-urlencode 'filter=tags:"public" AND settings.visibility = "public"'
{"results":[{"id":"1","title":"New Chat!","userLimit":10,"tags":["new","public"],"admin":"users/1","settings":{"visibility":"public"}},{"id":"4","title":"Team Chat","userLimit":50,"tags":["public"],"admin":"users/1","settings":{"visibility":"public"}}]}

$ curl -s -G localhost:8122/chatRooms --data-urlencode 'filter=endsWith(title, "Chat!")'
{"results":[{"id":"1","title":"New Chat!","userLimit":10,"tags":["new","public"],"admin":"users/1","settings":{"visibility":"public"}},{"id":"2","title":"Old Chat!","userLimit":3,"tags":["old"],"admin":"users/2","settings":{"visibility":"private"}},{"id":"3","title":"New Chat!","userLimit":2,"tags":["new"],"admin":"users/2","settings":{"visibility":"private"}}]}
```

タイポ、型違い、別リソースへの参照、配列への等号は、どれも位置付きの 400 Bad Request です。

```
$ curl -s -i -G localhost:8122/chatRooms --data-urlencode 'filter=ttile = "New Chat!"'
HTTP/1.1 400 Bad Request
Content-Type: text/plain; charset=utf-8

invalid filter: invalid field "ttile" at position 0

$ curl -s -i -G localhost:8122/chatRooms --data-urlencode 'filter=userLimit = "5"'
HTTP/1.1 400 Bad Request
Content-Type: text/plain; charset=utf-8

invalid filter: field is a number; cannot compare with "5" at position 12

$ curl -s -i -G localhost:8122/chatRooms --data-urlencode 'filter=admin.name = "Luca"'
HTTP/1.1 400 Bad Request
Content-Type: text/plain; charset=utf-8

invalid filter: invalid field "admin.name" at position 0

$ curl -s -i -G localhost:8122/chatRooms --data-urlencode 'filter=tags = "new"'
HTTP/1.1 400 Bad Request
Content-Type: text/plain; charset=utf-8

invalid filter: field is an array; use field:"value" at position 5
```

## 5. 1 リクエストの流れ
本番でリクエストがサーバーの中をどう通るかを、順に追います。
送る側を利用者、受ける側をサーバーと呼びます。

1. 利用者が `GET /chatRooms?filter=...` を送る。`filter` は URL エンコードされた文字列 1 つ
2. サーバーは `filter` を読む。空なら全件を対象にする
3. 対象のリソースを 1 件取り出し、`filter` を字句に分けてから、そのリソース 1 件だけを相手に式を評価する
4. 評価の途中で未知のフィールド、型の不一致、構文の誤りに当たったら、その場で 400 を返して終わる
5. 式が真になったリソースだけを `results` に積む
6. 全件見終わったら `results` を 200 で返す。ページ分割を併用する時は、絞った結果にページ分割がかかる

## 6. 疑問と答え
読みながら引っかかったところです。

**なぜ JSON のような構造化された条件ではなく、文字列なのか**
構文の追加や変更をサーバー側だけで済ませられるからです。
構造化すると条件の形が API 定義の一部になり、増やすたびに利用者側の対応が要ります。
SQL に慣れた人には文字列の方が読みやすく、条件が複雑になるほど差が出る、というのが書籍の 22.3.1 の比較でした。

**比較の右側に別のフィールドや別のリソースを置けないのはなぜか**
評価の入力をフィルター文字列とリソース 1 件に限定して、実行時間の上限を読めるようにするためです。
参照先を取りに行けるようにすると、どこまで辿れるか、取得に失敗したらどうするか、鮮度はどうか、と決めることが増え続けます。

**`tags[0] = "new"` のような位置の指定はなぜだめなのか**
配列の順序に意味を持たせることになり、追加はどこに入るのか、並べ替えたら値が変わるのか、といった決まりが要るからです。
含むかどうかだけを提供し、順序が必要なら `position` のようなフィールドを別に持たせます。

**打ち間違えたフィールド名を無視して全件返すのではなく、なぜエラーにするのか**
読み取りだけなら実害は小さいのですが、第 19 章の purge のように `filter` で削除する場面では致命的です。
位置付きのエラーを返す方が、黙って違う結果を返すより利用者の時間を奪いません。

**ワイルドカード（`title = "*(new)"`）は使えないのか**
構文にワイルドカードを足すと、`*` 自体をマッチさせるためのエスケープが必要になります。
代わりに `endsWith(title, "(new)")` のような関数にすれば、構文はそのままで機能だけ増やせます。

**ページ分割と同じリクエストに同居するのか**
します。
`filter`、`maxPageSize`、`pageToken` の 3 つが list リクエストの定番で、`filter` で絞った結果にページ分割がかかります。

ここまでを自分の言葉でまとめると、`filter` は文字列で受け取り、サーバーがリソース 1 件だけを相手に評価し、曖昧な式は推測せずに 400 で返す、です。

## 7. トレードオフ
得られるのは、利用者が全件を転送せずに済むことと、サーバー側の帯域と計算資源の節約です。
引き換えに、構文を決めて解析器を書き、ドキュメントを維持する手間がサーバー側に残ります。
文字列にするか構造化するかの選択も付いて回りますが、書籍は、時間が経っても API 定義を変えずに済む文字列を選んでいます。

書籍は、取得される件数が数百から数千になる一覧の list にはまず付けるよう勧めています。
構文はゼロから作らず、CEL や AIP-160 のような既存の仕様を参考にする前提です。

## 8. 参考
- 『APIデザイン・パターン』JJ Geewax 著、マイナビ出版、第 22 章
- https://google.aip.dev/160
- AWS EC2 の `DescribeInstances` は、フィルター名と値の配列を `Filter.N` に並べる構造化の形です。書籍の分類では構造化インターフェースに当たり、`instance-type` や `tag:<key>` のように使えるフィルター名がドキュメントに列挙されています: https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_DescribeInstances.html
