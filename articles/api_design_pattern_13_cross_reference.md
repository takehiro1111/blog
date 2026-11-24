---
title: "[Go]APIデザインパターン 13: 相互参照（使う/使わないの前後比較）"
emoji: "📘"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Go", "API", "設計", "デザインパターン"]
published: false
---
![](/images/go/go_logo.png =450x)

## 本記事の内容
- 『APIデザイン・パターン』(JJ Geewax 著、マイナビ出版) の第 13 章「相互参照」を、Go で書き直しながら読んだメモです
- パターンを使わない実装と使う実装を同じ手順で動かして、何が変わるかを出力で確かめます
- コードは Go 1.22 以降の `net/http` と標準ライブラリだけで動きます
- シリーズの目次は「[Go]APIデザインパターン 00: 目次と、パターンを使わないとどうなるか」にあります

## 1. 結論
別のリソースを指すフィールドは、参照先の識別子を文字列で持ち、`authorId` のように名前を `Id` で終えます。
参照先が消えても参照はそのまま残します。
サーバーは参照先の削除を止めず、参照を `null` に直すこともしません。
参照先の値（著者名など）のコピーは持たず、必要になった利用者が参照先を取りに行きます。

参照先の種類が 1 つに決まらない時は、`targetId` と `targetType` の 2 つで持ちます。

## 2. 困る場面
本（`Book`）と著者（`Author`）の API を考えます。
本の画面には著者名も出したいので、本のレスポンスに著者を埋め込みたくなります。
私も最初はそれで良いと思いました。

ところが、著者が消えたり名前が変わったりした時に、本の側が何を返すべきかが決まりません。
本を更新するリクエストで著者名まで書き換えられるのか、という読み方の問題も出てきます。
著者の項目が増えるほど、本のレスポンスも一緒に膨らみます。

参照先が消えた時の扱いには 3 つの選択肢があります。
参照されている間は削除を禁止する、削除と同時に参照を `null` にする、何もしないで利用者に任せる、の 3 つです。
書籍は 3 つ目を選びます。
4-2 では、埋め込んだ著者が消えた時に何が返るかを見ます。

## 3. 足すもの
`Book` には著者の識別子だけを `authorId` として持たせます。
値は `authors/1` のような文字列で、型による検査はありません。

参照先の削除は止めません。
禁止にすると、互いに参照し合う 2 つのリソース（著者のお気に入りの本と、本の著者）がどちらも消せなくなります。
削除時に参照を `null` に直す方法も採りません。
多作な著者を 1 人消すと何千冊もの本を更新することになり、途中で失敗すれば結局無効な参照が残るからです。

参照先の種類が固定でない時は、識別子と一緒に種類を持ちます。
変更履歴のように、本も著者も指せるリソースがその例です。

| フィールド | 中身 | 名前の付け方 |
|---|---|---|
| `authorId` | `authors/1` という識別子 | `Id` で終える |
| `author` | `Author` のコピー | `Id` を付けない |
| `targetId` + `targetType` | 識別子と、参照先の種類 | 種類が決まらない参照に使う |

Go の型にするとこうなります。

```go
type Book struct {
	ID       string `json:"id"`
	AuthorID string `json:"authorId"` // ①
	Title    string `json:"title"`
}

type Author struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type ChangeLogEntry struct {
	ID          string `json:"id"`
	TargetID    string `json:"targetId"` // ②
	TargetType  string `json:"targetType"`
	Description string `json:"description"`
}
```

- ① 著者の名前は持ちません。識別子の文字列だけです
- ② `targetType` には `Author` や `Book` のような参照先の種類が入ります

## 4. 前後比較
### 4-1. 使わない場合
本のレスポンスに著者を埋め込む形です。
サーバーは本を返す時に、著者の map を引いて `author` を組み立てます。

```go
type Book struct {
	ID     string `json:"id"`
	Title  string `json:"title"`
	Author Author `json:"author"` // ①
}

type bookRecord struct{ id, title, authorID string }

type store struct {
	mu        sync.Mutex
	authorSeq int
	bookSeq   int
	authors   map[string]Author
	books     map[string]bookRecord
}

func (s *store) view(b bookRecord) Book {
	return Book{ID: b.id, Title: b.title, Author: s.authors[b.authorID]} // ②
}

func main() {
	s := &store{authors: map[string]Author{}, books: map[string]bookRecord{}}
	mux := http.NewServeMux()

	mux.HandleFunc("DELETE /authors/{n}", func(w http.ResponseWriter, req *http.Request) {
		s.mu.Lock()
		delete(s.authors, "authors/"+req.PathValue("n"))
		s.mu.Unlock()
		w.WriteHeader(http.StatusOK)
	})

	mux.HandleFunc("POST /books", func(w http.ResponseWriter, req *http.Request) {
		var in struct {
			Title  string `json:"title"`
			Author struct {
				ID string `json:"id"`
			} `json:"author"`
		}
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		s.mu.Lock()
		s.bookSeq++
		b := bookRecord{id: "books/" + strconv.Itoa(s.bookSeq), title: in.Title, authorID: in.Author.ID}
		s.books[b.id] = b
		out := s.view(b)
		s.mu.Unlock()
		writeJSON(w, http.StatusOK, out)
	})

	mux.HandleFunc("GET /books/{n}", func(w http.ResponseWriter, req *http.Request) {
		s.mu.Lock()
		b, ok := s.books["books/"+req.PathValue("n")]
		out := s.view(b)
		s.mu.Unlock()
		if !ok {
			http.Error(w, "book not found", http.StatusNotFound)
			return
		}
		writeJSON(w, http.StatusOK, out)
	})

	log.Fatal(http.ListenAndServe(":8013", mux))
}
```

- ① レスポンスには `Author` の値がそのまま入ります
- ② 本を返すたびに著者を引いて埋めます。著者が無い時のことは考えていません

### 4-2. 動かすと消えた著者が空のまま返る
著者を作り、その著者の本を作ってから、著者を消します。

```
$ curl -s -i -X POST localhost:8013/authors -d '{"name":"Michelle Obama"}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"authors/1","name":"Michelle Obama"}

$ curl -s -i -X POST localhost:8013/books \
    -d '{"title":"Becoming","author":{"id":"authors/1"}}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"books/1","title":"Becoming","author":{"id":"authors/1","name":"Michelle Obama"}}

$ curl -s -i -X DELETE localhost:8013/authors/1
HTTP/1.1 200 OK

$ curl -s -i localhost:8013/books/1
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"books/1","title":"Becoming","author":{"id":"","name":""}}
```

本は 200 OK で返りますが、著者は `id` も `name` も空です。
利用者から見ると、「著者が消えた」のか「著者が未設定の本」なのか区別できません。
著者の名前を変えた場合も同じで、本を返すたびに引き直す実装なら新しい名前が、作成時にコピーする実装なら古い名前が返ります。
どちらが正しいかは API の約束次第で、利用者には分かりません。

:::message
Go の `map` は、無いキーを引くとその型のゼロ値を返します。
`Author` なら `id` も `name` も空文字の `Author{}` です。
2 つ目の戻り値 `ok` を見ない限り、「無い」と「空」の区別はつきません。
上の出力はこれが原因です。
:::

### 4-3. 使う場合（差分）
`Book` が持つのは `authorId` だけになり、サーバーは著者を引きません。
代わりに `GET /authors/{n}` を用意して、消えていれば 404 Not Found を返します。

```diff go
 type Book struct {
-	ID     string `json:"id"`
-	Title  string `json:"title"`
-	Author Author `json:"author"`
+	ID       string `json:"id"`
+	AuthorID string `json:"authorId"` // ①
+	Title    string `json:"title"`
 }

-type bookRecord struct{ id, title, authorID string }
+type ChangeLogEntry struct {
+	ID          string `json:"id"`
+	TargetID    string `json:"targetId"` // ②
+	TargetType  string `json:"targetType"`
+	Description string `json:"description"`
+}

 type store struct {
 	mu        sync.Mutex
 	authorSeq int
 	bookSeq   int
 	authors   map[string]Author
-	books     map[string]bookRecord
-}
-
-func (s *store) view(b bookRecord) Book {
-	return Book{ID: b.id, Title: b.title, Author: s.authors[b.authorID]}
+	books     map[string]Book
 }

+	mux.HandleFunc("GET /authors/{n}", func(w http.ResponseWriter, req *http.Request) {
+		s.mu.Lock()
+		a, ok := s.authors["authors/"+req.PathValue("n")]
+		s.mu.Unlock()
+		if !ok {
+			http.Error(w, "author not found", http.StatusNotFound) // ③
+			return
+		}
+		writeJSON(w, http.StatusOK, a)
+	})
+
 	mux.HandleFunc("POST /books", func(w http.ResponseWriter, req *http.Request) {
-		var in struct {
-			Title  string `json:"title"`
-			Author struct {
-				ID string `json:"id"`
-			} `json:"author"`
-		}
-		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
+		var b Book
+		if err := json.NewDecoder(req.Body).Decode(&b); err != nil {
 			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
 			return
 		}
 		s.mu.Lock()
 		s.bookSeq++
-		b := bookRecord{id: "books/" + strconv.Itoa(s.bookSeq), title: in.Title, authorID: in.Author.ID}
-		s.books[b.id] = b
-		out := s.view(b)
+		b.ID = "books/" + strconv.Itoa(s.bookSeq)
+		s.books[b.ID] = b
 		s.mu.Unlock()
-		writeJSON(w, http.StatusOK, out)
+		writeJSON(w, http.StatusOK, b)
 	})

 	mux.HandleFunc("GET /books/{n}", func(w http.ResponseWriter, req *http.Request) {
 		s.mu.Lock()
 		b, ok := s.books["books/"+req.PathValue("n")]
-		out := s.view(b)
 		s.mu.Unlock()
 		if !ok {
 			http.Error(w, "book not found", http.StatusNotFound)
 			return
 		}
-		writeJSON(w, http.StatusOK, out)
+		writeJSON(w, http.StatusOK, b) // ④
 	})
```

- ① リクエストもレスポンスも `authorId` の文字列だけです
- ② 変更履歴のように参照先の種類が決まらないリソースは、識別子と種類を一緒に持ちます
- ③ 参照先を取りに来た利用者に、消えたことを 404 で伝えます
- ④ 保存した `Book` をそのまま返します。著者の map は見ません

`DELETE /authors/{n}` は 4-1 と同じで、本から参照されていても止めません。

:::message
`json.NewDecoder(req.Body).Decode(&b)` で `Book` に直接入れていますが、`id` は後からサーバーが上書きしています。
利用者が `id` を送ってきても無視される、という動きです。
第 6 章で扱う識別子の決め方（利用者に選ばせない）に合わせています。
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

type Author struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type Book struct {
	ID       string `json:"id"`
	AuthorID string `json:"authorId"`
	Title    string `json:"title"`
}

type ChangeLogEntry struct {
	ID          string `json:"id"`
	TargetID    string `json:"targetId"`
	TargetType  string `json:"targetType"`
	Description string `json:"description"`
}

type store struct {
	mu        sync.Mutex
	authorSeq int
	bookSeq   int
	authors   map[string]Author
	books     map[string]Book
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func main() {
	s := &store{authors: map[string]Author{}, books: map[string]Book{}}
	mux := http.NewServeMux()

	mux.HandleFunc("POST /authors", func(w http.ResponseWriter, req *http.Request) {
		var a Author
		if err := json.NewDecoder(req.Body).Decode(&a); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		s.mu.Lock()
		s.authorSeq++
		a.ID = "authors/" + strconv.Itoa(s.authorSeq)
		s.authors[a.ID] = a
		s.mu.Unlock()
		writeJSON(w, http.StatusOK, a)
	})

	mux.HandleFunc("GET /authors/{n}", func(w http.ResponseWriter, req *http.Request) {
		s.mu.Lock()
		a, ok := s.authors["authors/"+req.PathValue("n")]
		s.mu.Unlock()
		if !ok {
			http.Error(w, "author not found", http.StatusNotFound)
			return
		}
		writeJSON(w, http.StatusOK, a)
	})

	mux.HandleFunc("DELETE /authors/{n}", func(w http.ResponseWriter, req *http.Request) {
		s.mu.Lock()
		delete(s.authors, "authors/"+req.PathValue("n"))
		s.mu.Unlock()
		w.WriteHeader(http.StatusOK)
	})

	mux.HandleFunc("POST /books", func(w http.ResponseWriter, req *http.Request) {
		var b Book
		if err := json.NewDecoder(req.Body).Decode(&b); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		s.mu.Lock()
		s.bookSeq++
		b.ID = "books/" + strconv.Itoa(s.bookSeq)
		s.books[b.ID] = b
		s.mu.Unlock()
		writeJSON(w, http.StatusOK, b)
	})

	mux.HandleFunc("GET /books/{n}", func(w http.ResponseWriter, req *http.Request) {
		s.mu.Lock()
		b, ok := s.books["books/"+req.PathValue("n")]
		s.mu.Unlock()
		if !ok {
			http.Error(w, "book not found", http.StatusNotFound)
			return
		}
		writeJSON(w, http.StatusOK, b)
	})

	log.Fatal(http.ListenAndServe(":8113", mux))
}
```
:::

### 4-4. 同じ手順で動かすと参照だけが残り、取りに行った時に 404 になる
同じ順番で、著者を作って本を作り、著者を消します。

```
$ curl -s -i -X POST localhost:8113/authors -d '{"name":"Michelle Obama"}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"authors/1","name":"Michelle Obama"}

$ curl -s -i -X POST localhost:8113/books \
    -d '{"title":"Becoming","authorId":"authors/1"}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"books/1","authorId":"authors/1","title":"Becoming"}

$ curl -s -i -X DELETE localhost:8113/authors/1
HTTP/1.1 200 OK

$ curl -s -i localhost:8113/books/1
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"books/1","authorId":"authors/1","title":"Becoming"}

$ curl -s -i localhost:8113/authors/1
HTTP/1.1 404 Not Found
Content-Type: text/plain; charset=utf-8

author not found
```

本には `authors/1` という参照が残ったままです。
著者名が欲しい利用者が `GET /authors/1` を呼ぶと 404 が返るので、そこで初めて「消えた」と分かります。
空の著者が黙って返ってくる 4-2 と違い、消えたことがステータスコードで伝わります。

## 5. 1 リクエストの流れ
本の画面を出す利用者のリクエストを、本番の順に追います。

1. 利用者が `GET /books/1` を送る
2. サーバーは `books` の map から本を引き、`authorId` を含めてそのまま 200 で返す。著者の map は見ない
3. 利用者は `authorId` の値で `GET /authors/1` を送る
4. サーバーは `authors` の map を引き、有れば 200 で `Author` を、無ければ 404 を返す
5. 利用者は 404 の時に「著者不明」と表示するなど、自分で扱いを決める

呼び出しが 2 回になることが、このパターンの払う代価です。
書籍は、1 回の問い合わせで本と著者をつなげて取りたいなら、GraphQL のような仕組みを API の上に重ねることを勧めています。

## 6. 疑問と答え
読みながら引っかかったところです。

**`author` ではなく `authorId` と名付ける理由は何か**
名前だけで、参照（識別子の文字列）なのか値（コピー）なのかが分かるようにするためです。
`Id` で終わるフィールドは識別子、終わらないフィールドはコピー、という約束にしています。

**参照されている間は削除を禁止すれば、壊れないのでは**
互いに参照し合う 2 つのリソースがあると、どちらも消せなくなります。
著者のお気に入りの本と、本の著者が、お互いを指している状態がそれです。
多作な著者を消すために数千冊の本を先に消す羽目にもなります。

**削除した時に参照を `null` に直せばよいのでは**
参照している側が数千件あると、1 回の削除が数千件の更新になります。
途中で失敗すればやはり無効な参照が残るので、アトミックにできない処理を抱え込むだけになります。

**2 回呼ぶのが面倒なので埋め込みたい**
埋め込むと、古くなった値をどう直すか、本の更新で著者名を変えてよいのか、という問題が増えます。
書籍は、API 自体は参照だけにしておき、まとめて取る手段は GraphQL のような別の層に任せる、という立場です。

**参照先の種類が 1 つに決まらない時はどうするか**
識別子と種類を別のフィールドで持ちます。
変更履歴なら `targetId` と `targetType` の組です。

**作成時に `authorId` の存在を確かめなくてよいのか**
確かめても、後で著者が消えれば同じことなので、保証にはなりません。
存在しない識別子を 400 で断ること自体は構いませんが、その後の整合性は利用者側で扱う前提は変わりません。

ここまでを自分の言葉でまとめると、参照は `xxxId` の文字列だけで持ち、参照先が消えても直さず、取りに行った利用者が 404 で気付く、です。

## 7. トレードオフ
得られるのは、参照先をいつでも消せること、循環参照で詰まらないこと、1 つのリソースが何千もの参照を受けても削除が重くならないことです。
引き換えに、関連する情報を取るための API 呼び出しが増えます。
参照が無効になっていることを、利用者が常に想定しなければならない点も負担です。

書籍は、参照だけで API を組み、つなげて取る必要があれば GraphQL のような仕組みを使う、という進め方を勧めています。

## 8. 参考
- 『APIデザイン・パターン』JJ Geewax 著、マイナビ出版、第 13 章
- https://google.aip.dev/122
