---
title: "[Go]APIデザインパターン 05: データ型とデフォルト値（使う/使わないの前後比較）"
emoji: "📘"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Go", "API", "設計", "デザインパターン"]
published: false
---
![](/images/go/go_logo.png =450x)

## 本記事の内容
- 『APIデザイン・パターン』(JJ Geewax 著、マイナビ出版) の第 5 章「データ型とデフォルト値」を、Go で書き直しながら読んだメモです
- 値が無い時の扱いを決めていない API と決めた API を同じ手順で動かして、出力の違いを確かめます
- コードは Go 1.22 以降の `net/http` と標準ライブラリだけで動きます
- シリーズの目次は「[Go]APIデザインパターン 00: 目次と、パターンを使わないとどうなるか」にあります

## 1. 結論
API のフィールドは、値がある時より無い時の扱いで困ります。
「キーが無い」「null」「空文字列や 0」の 3 つをどう扱うかを型ごとに決めて、ドキュメントに書き、サーバー側で検証します。
Go の `string` 型のフィールドで受けると 3 つとも `""` になって区別がつかないので、区別したければ `*string` か、キーの有無を自分で記録する型で受けます。

型ごとの決め事は 3 節にまとめました。
動かして比べるのは、文字列の null とキー無しです。

## 2. 困る場面
読んでいて最初に引っかかったのは、これが JSON の仕様の話ではなく、API の約束の話だということでした。
利用者はそれぞれ違うライブラリで JSON を作るので、ライブラリが良きに計らってくれる前提は置けません。

書籍は果物のリソースで 4 つの入力を並べています。

```
fruit1 = { name: "Apple", color: "red" }
fruit2 = { name: "Apple", color: "" }
fruit3 = { name: "Apple", color: null }
fruit4 = { name: "Apple" }
```

`fruit1` は迷いません。
残りの 3 つは、「色が無い」のか、「色はサーバーに任せる」のか、「色については何も言っていない」のか、API が決めていなければ利用者ごとに解釈が変わります。

実害が出るのは更新です。
名前だけ変えたい利用者が `{"name":"Fuji"}` を送った時に、サーバーが「color は空」と受け取ると、せっかく付けた色が消えます。
4-2 で、色が消えるところを見ます。

## 3. 足すもの
足すのは、型ごとの扱いの決め事と、それを受け取れる Go の型です。

まず Go 側で、4 つの入力がどう見えるかを確かめました。
`string`、`*string`、キーの有無を記録する自作の型の 3 通りで、同じ JSON を読みます。

```go
type FruitString struct {
	Name  string `json:"name"`
	Color string `json:"color"` // ①
}

type FruitPointer struct {
	Name  string  `json:"name"`
	Color *string `json:"color"` // ②
}

type OptionalString struct { // ③
	Set   bool
	Valid bool
	Value string
}

func (o *OptionalString) UnmarshalJSON(b []byte) error {
	o.Set = true
	if string(b) == "null" {
		return nil
	}
	o.Valid = true
	return json.Unmarshal(b, &o.Value)
}
```

- ① `string` はゼロ値が `""` なので、null もキー無しも `""` になります
- ② `*string` は null とキー無しが nil になり、`""` とは区別できます
- ③ `UnmarshalJSON` はキーがある時だけ呼ばれるので、呼ばれたら `Set` を立てます。null なら `Valid` を立てずに戻ります

実行結果です。

| 入力 | `string` | `*string` | `OptionalString` |
|---|---|---|---|
| `"color":"red"` | `"red"` | `"red"` | Set, Valid, `"red"` |
| `"color":""` | `""` | `""` | Set, Valid, `""` |
| `"color":null` | `""` | nil | Set のみ |
| キー無し | `""` | nil | どちらも false |

3 つを全部区別できるのは `OptionalString` だけです。

:::message
`encoding/json` は、JSON に無いキーはフィールドをゼロ値のまま残し、JSON の null はポインタでないフィールドには何もしません。
ポインタのフィールドなら、null で nil になります。
`UnmarshalJSON` を持つ型を値（ポインタでない）のフィールドにしておくと、null の時もメソッドが呼ばれて自分で判断できます。
:::

型ごとの決め事は、書籍の順に書きます。

ブール値は、true が肯定の意味になる名前にします。
`disallowChatbots` だと、許可されているかを `=== false` で確かめる二重否定になります。
ただし、ゼロ値が false になる形式で「未指定なら許可」にしたい時は、あえて `disallowChatbots` にしてゼロ値を望む既定値にする、という逆向きの使い方も書籍は認めています。

数値は、足したり平均したりする値にだけ使い、識別子は数字に見えても文字列にします。
内部は 64 ビットを前提にし、それより大きい整数や小数は文字列で送ります。
`9999999999999999999999999` と `9999999999999999999999998` を数値として読むと、Go の `float64` でも同じ `1e+25` になり、等しいと判定されました。

文字列は UTF-8 にそろえ、識別子に使うものは正規化形式 C にして、同じ見た目の別バイト列を作らないようにします。
上限を超える入力は、切り詰めずに拒否します。

列挙型は Web API では使わず、文字列にしてサーバーで検証します。
`2` より `"blue"` の方がログで読めますし、新しい値を足した時に利用者側の列挙の写しを更新しなくて済みます。

リストは丸ごと置き換える単位にして、2 番目だけ更新するようなメソッドは作りません。
要素数の上限を決め、超えたら拒否します。

マップはキーを文字列にして、キーと値の数とサイズに上限を決めます。
マップは null と `{}` が区別しやすいので、null を「サーバーに任せる」、`{}` を「空にする」と決められます。

## 4. 前後比較
### 4-1. 使わない場合
`Fruit` を `string` のフィールドで受け、更新は受け取った struct で丸ごと置き換える形です。

```go
type Fruit struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Color string `json:"color,omitempty"` // ①
}

func main() {
	s := &store{fruits: map[string]Fruit{}}
	mux := http.NewServeMux()

	mux.HandleFunc("POST /fruits", func(w http.ResponseWriter, req *http.Request) {
		var in Fruit
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		s.mu.Lock()
		defer s.mu.Unlock()
		in.ID = strconv.Itoa(len(s.fruits) + 1)
		s.fruits[in.ID] = in
		writeJSON(w, http.StatusOK, in)
	})

	mux.HandleFunc("PATCH /fruits/{id}", func(w http.ResponseWriter, req *http.Request) {
		var in Fruit
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		s.mu.Lock()
		defer s.mu.Unlock()
		id := req.PathValue("id")
		if _, ok := s.fruits[id]; !ok {
			http.Error(w, "fruit not found", http.StatusNotFound)
			return
		}
		in.ID = id
		s.fruits[id] = in // ②
		writeJSON(w, http.StatusOK, in)
	})

	log.Fatal(http.ListenAndServe(":8005", mux))
}
```

- ① `omitempty` は、値が `""` の時にレスポンスからキーごと消します
- ② 受け取った struct をそのまま保存します。送られてこなかったフィールドはゼロ値で上書きされます

### 4-2. 動かすと色が消える
赤いリンゴを作ってから、名前だけ変えます。

```
$ curl -s -i -X POST localhost:8005/fruits -d '{"name":"Apple","color":"red"}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","name":"Apple","color":"red"}

$ curl -s -i -X PATCH localhost:8005/fruits/1 -d '{"name":"Fuji"}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","name":"Fuji"}

$ curl -s localhost:8005/fruits/1
{"id":"1","name":"Fuji"}
```

色が消えました。
`omitempty` のせいで `color` のキーごと無くなっているので、`""` になったことすらレスポンスからは分かりません。
null を送っても `""` を送っても、同じ結果です。

```
$ curl -s -X PATCH localhost:8005/fruits/1 -d '{"name":"Fuji","color":null}'
{"id":"1","name":"Fuji"}

$ curl -s -X PATCH localhost:8005/fruits/1 -d '{"name":"Fuji","color":""}'
{"id":"1","name":"Fuji"}
```

3 通りの入力が同じ結果になり、利用者が何を伝えたかったのかをサーバーは受け取れていません。

### 4-3. 使う場合（差分）
決め事はこうです。
キーが無ければそのフィールドには触らず、null なら「色なし」に戻し、`""` は色として無効なので 400 Bad Request にします。
`color` は `*string` で持ち、色なしはレスポンスに `null` と書きます。

```diff go
 type Fruit struct {
-	ID    string `json:"id"`
-	Name  string `json:"name"`
-	Color string `json:"color,omitempty"`
+	ID    string  `json:"id"`
+	Name  string  `json:"name"`
+	Color *string `json:"color"` // ①
 }
+
+type OptionalString struct { // ②
+	Set   bool
+	Valid bool
+	Value string
+}
+
+func (o *OptionalString) UnmarshalJSON(b []byte) error {
+	o.Set = true
+	if string(b) == "null" {
+		return nil
+	}
+	o.Valid = true
+	return json.Unmarshal(b, &o.Value)
+}
+
+type UpdateFruitRequest struct {
+	Name  OptionalString `json:"name"`
+	Color OptionalString `json:"color"`
+}

 	mux.HandleFunc("PATCH /fruits/{id}", func(w http.ResponseWriter, req *http.Request) {
-		var in Fruit
+		var in UpdateFruitRequest
 		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
 			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
 			return
 		}
 		s.mu.Lock()
 		defer s.mu.Unlock()
-		id := req.PathValue("id")
-		if _, ok := s.fruits[id]; !ok {
+		cur, ok := s.fruits[req.PathValue("id")]
+		if !ok {
 			http.Error(w, "fruit not found", http.StatusNotFound)
 			return
 		}
-		in.ID = id
-		s.fruits[id] = in
-		writeJSON(w, http.StatusOK, in)
+		if in.Name.Set { // ③
+			if !in.Name.Valid || in.Name.Value == "" {
+				http.Error(w, "name must be a non-empty string", http.StatusBadRequest)
+				return
+			}
+			cur.Name = in.Name.Value
+		}
+		if in.Color.Set {
+			switch {
+			case !in.Color.Valid: // ④
+				cur.Color = nil
+			case in.Color.Value == "": // ⑤
+				http.Error(w, "color must not be empty", http.StatusBadRequest)
+				return
+			default:
+				cur.Color = &in.Color.Value
+			}
+		}
+		s.fruits[cur.ID] = cur
+		writeJSON(w, http.StatusOK, cur)
 	})
```

- ① nil が「色なし」です。`omitempty` を外したので、nil はレスポンスに `null` と出ます
- ② キーが来たか、null でなかったか、を値と一緒に持ちます
- ③ キーが無いフィールドには触りません。これで名前だけの更新が安全になります
- ④ null は「色なし」に戻します
- ⑤ `""` は色として無効なので断ります

作成（`POST /fruits`）も同じ型で受け、`name` が無ければ 400 にしています。

:::message
`*string` が nil の時、`encoding/json` はレスポンスに `null` と書きます。
`omitempty` を付けるとキーごと消えてしまうので、「色を消した」ことを利用者に見せたい時は付けません。
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

type Fruit struct {
	ID    string  `json:"id"`
	Name  string  `json:"name"`
	Color *string `json:"color"` // ① nil は「色なし」。レスポンスには null と書く
}

type OptionalString struct { // ②
	Set   bool
	Valid bool
	Value string
}

func (o *OptionalString) UnmarshalJSON(b []byte) error {
	o.Set = true
	if string(b) == "null" {
		return nil
	}
	o.Valid = true
	return json.Unmarshal(b, &o.Value)
}

type CreateFruitRequest struct {
	Name  string         `json:"name"`
	Color OptionalString `json:"color"`
}

type UpdateFruitRequest struct {
	Name  OptionalString `json:"name"`
	Color OptionalString `json:"color"`
}

type store struct {
	mu     sync.Mutex
	fruits map[string]Fruit
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func main() {
	s := &store{fruits: map[string]Fruit{}}
	mux := http.NewServeMux()

	mux.HandleFunc("POST /fruits", func(w http.ResponseWriter, req *http.Request) {
		var in CreateFruitRequest
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		if in.Name == "" {
			http.Error(w, "name is required", http.StatusBadRequest)
			return
		}
		if in.Color.Set && in.Color.Valid && in.Color.Value == "" {
			http.Error(w, "color must not be empty", http.StatusBadRequest)
			return
		}
		f := Fruit{Name: in.Name}
		if in.Color.Valid {
			f.Color = &in.Color.Value
		}
		s.mu.Lock()
		defer s.mu.Unlock()
		f.ID = strconv.Itoa(len(s.fruits) + 1)
		s.fruits[f.ID] = f
		writeJSON(w, http.StatusOK, f)
	})

	mux.HandleFunc("PATCH /fruits/{id}", func(w http.ResponseWriter, req *http.Request) {
		var in UpdateFruitRequest
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		s.mu.Lock()
		defer s.mu.Unlock()
		cur, ok := s.fruits[req.PathValue("id")]
		if !ok {
			http.Error(w, "fruit not found", http.StatusNotFound)
			return
		}
		if in.Name.Set { // ③ キーが無ければ触らない
			if !in.Name.Valid || in.Name.Value == "" {
				http.Error(w, "name must be a non-empty string", http.StatusBadRequest)
				return
			}
			cur.Name = in.Name.Value
		}
		if in.Color.Set {
			switch {
			case !in.Color.Valid: // ④ null は「色なし」に戻す
				cur.Color = nil
			case in.Color.Value == "": // ⑤ 空文字列は色として無効
				http.Error(w, "color must not be empty", http.StatusBadRequest)
				return
			default:
				cur.Color = &in.Color.Value
			}
		}
		s.fruits[cur.ID] = cur
		writeJSON(w, http.StatusOK, cur)
	})

	mux.HandleFunc("GET /fruits/{id}", func(w http.ResponseWriter, req *http.Request) {
		s.mu.Lock()
		defer s.mu.Unlock()
		f, ok := s.fruits[req.PathValue("id")]
		if !ok {
			http.Error(w, "fruit not found", http.StatusNotFound)
			return
		}
		writeJSON(w, http.StatusOK, f)
	})

	log.Fatal(http.ListenAndServe(":8105", mux))
}
```
:::

### 4-4. 同じ手順で動かすと色が残る
4-2 と同じ手順です。

```
$ curl -s -i -X POST localhost:8105/fruits -d '{"name":"Apple","color":"red"}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","name":"Apple","color":"red"}

$ curl -s -i -X PATCH localhost:8105/fruits/1 -d '{"name":"Fuji"}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","name":"Fuji","color":"red"}
```

名前だけ変わり、色は残りました。
null と `""` は、別の結果になります。

```
$ curl -s -i -X PATCH localhost:8105/fruits/1 -d '{"color":null}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","name":"Fuji","color":null}

$ curl -s -i -X PATCH localhost:8105/fruits/1 -d '{"color":""}'
HTTP/1.1 400 Bad Request
Content-Type: text/plain; charset=utf-8

color must not be empty

$ curl -s localhost:8105/fruits/1
{"id":"1","name":"Fuji","color":null}
```

null で色なしに戻り、レスポンスにも `"color":null` と出るので、消えたことが見えます。
`""` は 400 で止まり、保存は変わりません。

## 5. 1 リクエストの流れ
4-3 の更新リクエストがサーバーの中をどう通るかです。
送る側を利用者、受ける側をサーバーと呼びます。

1. 利用者が変えたいキーだけを入れて `PATCH /fruits/1` を送る
2. サーバーは JSON を `UpdateFruitRequest` に読む。キーがあるフィールドだけ `UnmarshalJSON` が呼ばれ、`Set` が立つ
3. 現在の `Fruit` を取り出す。無ければ 404
4. `name` のキーがあれば、null と `""` を 400 で断り、それ以外は書き換える
5. `color` のキーがあれば、null なら nil に、`""` なら 400、それ以外は書き換える。キーが無ければ何もしない
6. 保存して、`color` が nil なら `null` と書いたレスポンスを 200 で返す

4-1 では 2 と 4 と 5 が無く、受け取った struct をそのまま保存していました。

## 6. 疑問と答え
読みながら引っかかったところです。

**null とキー無しを同じ扱いにしてはいけないのか**
決めてドキュメントに書けば、同じでも構いません。
更新では「キー無しは触らない」が一番事故が少ないので、この記事では null を「消す」、キー無しを「触らない」に分けました。
部分更新の本命の方法は第 8 章のフィールドマスクで、そこでは別の答えが出てきます。

**`""` を 400 にせず、既定値に戻す合図にしてはだめか**
書籍はその使い方も挙げています。
`""` がそのフィールドの有効な値でないなら、既定値に置き換える合図として使えます。
色には「既定値」が無いので、この記事では断る方にしました。

**ブール値はなぜ肯定形の名前がよいのか**
`disallowChatbots === false` のような二重否定を読まされるからです。
ただ、ゼロ値が false になる形式では、未指定の時に欲しい既定値が false になるように名前を決める、という逆の使い方もあります。

**識別子を数値にしてはいけない理由は**
足したり平均したりしない値は数値ではない、というのが書籍の線引きです。
数値にすると、大きな値で精度が落ちます。
3 節の実験では、1 違う 2 つの整数が `float64` で同じ値になりました。

**列挙型を避ける理由は**
`2` より `"blue"` の方が、リクエストのログを見た時にそのまま読めます。
サーバーが新しい値を足した時も、整数の列挙だと利用者が持つ写しを更新するまで意味が分かりません。
文字列ならサーバーで検証するだけで済みます。

**リストの 2 番目だけ更新したい時は**
作りません。
リストは丸ごと置き換える単位にし、要素を個別に扱いたくなったら、それは別のリソース（サブコレクション）にする合図と読みます。

ここまでを自分の言葉でまとめると、値が無い時の 3 通りを型ごとに決めてサーバーで守る、Go で区別したいならキーの有無を自分で記録する、です。

## 7. トレードオフ
得られるのは、利用者がどのライブラリで JSON を作っても同じ結果になることと、名前だけ変えたつもりで色が消えるような事故が無くなることです。
引き換えに、`OptionalString` のような型と分岐が増えます。
`*string` にすると nil の確認が Go のコードのあちこちに入り、数値を文字列で送れば計算のたびに変換が要ります。

書籍は、型ごとに扱いを決めてドキュメントに書き、検証はクライアントではなくサーバーで行う、という進め方を勧めています。
ゼロ値を特別な意味に使うのは、ゼロ値が本当に使われない時だけにします。

## 8. 参考
- 『APIデザイン・パターン』JJ Geewax 著、マイナビ出版、第 5 章
- https://google.aip.dev/129 （サーバーが補う値と既定値）
- https://google.aip.dev/149 （未設定のフィールド値）
- AWS SDK for Go v2 は、入力の省略可能なフィールドをポインタ型にしています。EC2 の `CreateVolumeInput` の `Size` は `*int32` で、`aws.String` や `aws.Int32` で値をポインタにして渡します。未指定（nil）とゼロ値を区別するための作りです: https://pkg.go.dev/github.com/aws/aws-sdk-go-v2/aws
