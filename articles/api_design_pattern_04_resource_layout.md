---
title: "[Go]APIデザインパターン 04: リソースの範囲と階層（使う/使わないの前後比較）"
emoji: "📘"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Go", "API", "設計", "デザインパターン"]
published: false
---
![](/images/go/go_logo.png =450x)

## 本記事の内容
- 『APIデザイン・パターン』(JJ Geewax 著、マイナビ出版) の第 4 章「リソースの範囲と階層」を、Go で書き直しながら読んだメモです
- 何でもリソースにした API と、必要なものだけリソースにした API を同じ手順で動かして、出力の違いを確かめます
- コードは Go 1.22 以降の `net/http` と標準ライブラリだけで動きます
- シリーズの目次は「[Go]APIデザインパターン 00: 目次と、パターンを使わないとどうなるか」にあります

## 1. 結論
API で何をリソースにし、リソース同士をどう結ぶかを、書籍はリソースレイアウトと呼んでいます。
決め方は 3 つに絞れます。
単独で作ったり消したりする必要があるものだけをリソースにして、それ以外はリソースの中のデータ型にします。
親子（階層）にするのは、親を消したら子も消える、親に触れる人は子にも触れる、という振る舞いが欲しい時だけです。
リソース同士の関係は、便利そうだからではなく、その API の目的に必要なものだけ持ちます。

この章も「設計の原則」の部にあり、パターンではありません。
ただ、決め方を外した時に何が起きるかは動かすと見えるので、同じ形で比べます。

## 2. 困る場面
読んでいて最初に引っかかったのは、「全部リソースにすると何が困るのか」でした。
数が増えて面倒、くらいにしか思っていなかったからです。

書籍の例は、画像にアノテーションを付ける API です。
登場する概念は、画像、アノテーション、バウンディングボックス、ノートの 4 つあります。
全部をリソースにすると、それぞれに作成・取得・一覧・更新・削除の 5 メソッドが要るので、20 メソッドになります。
それだけなら作ればよいのですが、1 つのアノテーションを作るのにリクエストが 3 回必要になり、2 回目で失敗するとバウンディングボックスの無いアノテーションが残ります。
4-2 で、その半端な状態が残るところを見ます。

書籍は他に 2 つのやりがちな形を挙げています。
階層を深くしすぎると、ドキュメント 1 つを取るのに大学・学校・コース・学期の 4 つの id が要るようになります。
逆に何でもインラインにすると、著者の名前を本ごとに写すことになり、著者名を変えた時にどの本を直すのかを利用者が考えることになります。

## 3. 足すもの
足すのは、リソースと関係を決める時の判断です。
書籍は関係を 4 種類に分けています。

| 種類 | 例 | 向き |
|---|---|---|
| 参照 | `Message.author` が `User` を指す | 多対一 |
| 多対多 | `ChatRoom` のメンバーと `User` | 双方向 |
| 自己参照 | `Employee.manager` が `Employee` を指す | 同じ型 |
| 階層 | `ChatRoom` が `Message` を持つ | 親が子を所有 |

関係を持つ前に、その関係が API の目的に必要かを考えます。
ユーザー同士のフォロー関係は SNS には必須ですが、ダイレクトメッセージの API で連絡先全員との関係を持ち続ける必要はありません。
何百万件もつながったリソースを 1 つ消すと、何百万件を更新することになるからです。

次に、参照にするかインラインにするかを決めます。
チャットルームの管理者を `adminUserId` で参照すると、名前を見るのに ChatRoom と User の 2 回の呼び出しが要ります。
インラインなら 1 回で済みますが、管理者の名前のように滅多に見ないデータを毎回返すことになります。
よくある使い方に合わせて決めます。

階層にするかは、2 つの振る舞いが欲しいかで決めます。
親を消した時に子も消えてほしいか、親にアクセスできる人は子にもアクセスできてほしいか、です。
両方欲しいなら階層にし、子が複数の親を持ちうるなら階層にしません。

最後に、リソースかデータ型かです。
関連するリソースと切り離して単独で操作する必要が無いなら、データ型で十分です。
書籍の例を Go の型にするとこうなります。

```go
type Image struct { // ①
	ID string `json:"id"`
}

type Annotation struct { // ①
	ID          string      `json:"id"`
	BoundingBox BoundingBox `json:"boundingBox"`
	Notes       []Note      `json:"notes"`
}

type BoundingBox struct { // ②
	BottomLeftPoint Point `json:"bottomLeftPoint"`
	TopRightPoint   Point `json:"topRightPoint"`
}

type Point struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

type Note struct { // ②
	Content    string    `json:"content"`
	CreateTime time.Time `json:"createTime"`
}
```

- ① `id` を持つ 2 つだけがリソースです
- ② バウンディングボックスはアノテーションと 1 対 1 で、ノートは数が増えないので、アノテーションの中のデータ型にします

## 4. 前後比較
### 4-1. 使わない場合
4 つ全部をリソースにし、URL も `/images/{image}/annotations/{annotation}/boundingBoxes` のように階層にした形です。
作成のハンドラだけ載せます。

```go
type Annotation struct { // ①
	ID    string `json:"id"`
	Image string `json:"image"`
}

type BoundingBox struct { // ②
	ID              string `json:"id"`
	Annotation      string `json:"annotation"`
	BottomLeftPoint Point  `json:"bottomLeftPoint"`
	TopRightPoint   Point  `json:"topRightPoint"`
}

type Note struct { // ②
	ID         string    `json:"id"`
	Annotation string    `json:"annotation"`
	Content    string    `json:"content"`
	CreateTime time.Time `json:"createTime"`
}

func main() {
	s := &store{annotations: map[string]Annotation{}, boxes: map[string]BoundingBox{}, notes: map[string]Note{}}
	mux := http.NewServeMux()

	mux.HandleFunc("POST /images/{image}/annotations", func(w http.ResponseWriter, req *http.Request) {
		s.mu.Lock()
		defer s.mu.Unlock()
		a := Annotation{ID: strconv.Itoa(len(s.annotations) + 1), Image: req.PathValue("image")}
		s.annotations[a.ID] = a // ③
		writeJSON(w, http.StatusOK, a)
	})

	mux.HandleFunc("POST /images/{image}/annotations/{annotation}/boundingBoxes", func(w http.ResponseWriter, req *http.Request) {
		var in BoundingBox
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		s.mu.Lock()
		defer s.mu.Unlock()
		if _, ok := s.annotations[req.PathValue("annotation")]; !ok {
			http.Error(w, "annotation not found", http.StatusNotFound)
			return
		}
		if !validBox(in) { // ④
			http.Error(w, "topRightPoint must be above and to the right of bottomLeftPoint", http.StatusBadRequest)
			return
		}
		in.ID = strconv.Itoa(len(s.boxes) + 1)
		in.Annotation = req.PathValue("annotation")
		s.boxes[in.ID] = in
		writeJSON(w, http.StatusOK, in)
	})

	// notes の POST と、各リソースの GET も同じ形で続く

	log.Fatal(http.ListenAndServe(":8004", mux))
}
```

- ① アノテーションは id と親の画像しか持ちません。中身は別のリソースにあります
- ② バウンディングボックスとノートも、id と親を持つリソースです
- ③ アノテーションは中身が無くても作れます
- ④ 座標の検証は、アノテーションが作られた後の 2 回目のリクエストで初めて走ります

:::message
`req.PathValue("image")` は Go 1.22 で入った機能で、パターンの `{image}` に一致した部分を取り出します。
`map` は複数のリクエストから同時に書き込むと panic するので、`sync.Mutex` で囲んでいます。
:::

### 4-2. 動かすと中身の無いアノテーションが残る
アノテーションを作り、座標が逆さまのバウンディングボックスを付けてみます。

```
$ curl -s -i -X POST localhost:8004/images/1/annotations -d '{}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","image":"1"}

$ curl -s -i -X POST localhost:8004/images/1/annotations/1/boundingBoxes \
    -d '{"bottomLeftPoint":{"x":10,"y":10},"topRightPoint":{"x":5,"y":5}}'
HTTP/1.1 400 Bad Request
Content-Type: text/plain; charset=utf-8

topRightPoint must be above and to the right of bottomLeftPoint

$ curl -s localhost:8004/images/1/annotations
{"results":[{"id":"1","image":"1"}]}

$ curl -s localhost:8004/images/1/annotations/1/boundingBoxes
{"results":[]}
```

2 回目が 400 になっても、1 回目で作ったアノテーションは残っています。
一覧には、バウンディングボックスを持たないアノテーションが見えます。
正しい座標でやり直しても、ノートまで入れるにはさらに 2 回のリクエストが要ります。

```
$ curl -s -X POST localhost:8004/images/1/annotations/1/boundingBoxes \
    -d '{"bottomLeftPoint":{"x":5,"y":5},"topRightPoint":{"x":10,"y":10}}'
{"id":"1","annotation":"1","bottomLeftPoint":{"x":5,"y":5},"topRightPoint":{"x":10,"y":10}}

$ curl -s -X POST localhost:8004/images/1/annotations/1/notes -d '{"content":"cat"}'
{"id":"1","annotation":"1","content":"cat","createTime":"2026-10-28T07:12:39.460422Z"}
```

読む時も同じで、アノテーション 1 つの中身を知るには 3 つの一覧を別々に取ることになります。

### 4-3. 使う場合（差分）
バウンディングボックスとノートをアノテーションの中に入れ、作成を 1 つのハンドラにまとめます。
`boundingBoxes` と `notes` の POST ハンドラは丸ごと無くなります。

```diff go
 type Annotation struct {
-	ID    string `json:"id"`
-	Image string `json:"image"`
+	ID          string      `json:"id"`
+	BoundingBox BoundingBox `json:"boundingBox"` // ①
+	Notes       []Note      `json:"notes"`
 }

 type BoundingBox struct {
-	ID              string `json:"id"`
-	Annotation      string `json:"annotation"`
 	BottomLeftPoint Point  `json:"bottomLeftPoint"`
 	TopRightPoint   Point  `json:"topRightPoint"`
 }

 type Note struct {
-	ID         string    `json:"id"`
-	Annotation string    `json:"annotation"`
 	Content    string    `json:"content"`
 	CreateTime time.Time `json:"createTime"`
 }

 	mux.HandleFunc("POST /images/{image}/annotations", func(w http.ResponseWriter, req *http.Request) {
+		var in Annotation
+		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
+			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
+			return
+		}
+		if !validBox(in.BoundingBox) { // ②
+			http.Error(w, "boundingBox.topRightPoint must be above and to the right of bottomLeftPoint", http.StatusBadRequest)
+			return
+		}
+		for i := range in.Notes {
+			if in.Notes[i].Content == "" {
+				http.Error(w, "notes["+strconv.Itoa(i)+"].content must not be empty", http.StatusBadRequest)
+				return
+			}
+			in.Notes[i].CreateTime = time.Now().UTC()
+		}
+		if in.Notes == nil {
+			in.Notes = []Note{}
+		}
 		s.mu.Lock()
 		defer s.mu.Unlock()
-		a := Annotation{ID: strconv.Itoa(len(s.annotations) + 1), Image: req.PathValue("image")}
-		s.annotations[a.ID] = a
-		writeJSON(w, http.StatusOK, a)
+		image := req.PathValue("image")
+		in.ID = strconv.Itoa(len(s.annotations[image]) + 1)
+		s.annotations[image] = append(s.annotations[image], in) // ③
+		writeJSON(w, http.StatusOK, in)
 	})
```

- ① バウンディングボックスとノートは id を持たず、アノテーションの一部になります
- ② 座標もノートも、保存する前に全部検証します。どれか 1 つでも失敗したら何も保存しません
- ③ 保存は 1 回で、アノテーションの中身がまとめて入ります

:::message
`in.Notes == nil` の分岐は、JSON の見た目のためです。
Go で nil のスライスを `encoding/json` で書くと `null` になり、空のスライスなら `[]` になります。
ノートが無い時に `"notes": null` ではなく `"notes": []` と返したいので、空のスライスに置き換えています。
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
	"time"
)

type Point struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

type Annotation struct { // ①
	ID          string      `json:"id"`
	BoundingBox BoundingBox `json:"boundingBox"`
	Notes       []Note      `json:"notes"`
}

type BoundingBox struct { // ②
	BottomLeftPoint Point `json:"bottomLeftPoint"`
	TopRightPoint   Point `json:"topRightPoint"`
}

type Note struct { // ②
	Content    string    `json:"content"`
	CreateTime time.Time `json:"createTime"`
}

type store struct {
	mu          sync.Mutex
	annotations map[string][]Annotation
}

func validBox(b BoundingBox) bool {
	return b.TopRightPoint.X > b.BottomLeftPoint.X && b.TopRightPoint.Y > b.BottomLeftPoint.Y
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func main() {
	s := &store{annotations: map[string][]Annotation{}}
	mux := http.NewServeMux()

	mux.HandleFunc("POST /images/{image}/annotations", func(w http.ResponseWriter, req *http.Request) {
		var in Annotation
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		if !validBox(in.BoundingBox) { // ③
			http.Error(w, "boundingBox.topRightPoint must be above and to the right of bottomLeftPoint", http.StatusBadRequest)
			return
		}
		for i := range in.Notes {
			if in.Notes[i].Content == "" {
				http.Error(w, "notes["+strconv.Itoa(i)+"].content must not be empty", http.StatusBadRequest)
				return
			}
			in.Notes[i].CreateTime = time.Now().UTC()
		}
		if in.Notes == nil {
			in.Notes = []Note{}
		}
		s.mu.Lock()
		defer s.mu.Unlock()
		image := req.PathValue("image")
		in.ID = strconv.Itoa(len(s.annotations[image]) + 1)
		s.annotations[image] = append(s.annotations[image], in) // ④
		writeJSON(w, http.StatusOK, in)
	})

	mux.HandleFunc("GET /images/{image}/annotations", func(w http.ResponseWriter, req *http.Request) {
		s.mu.Lock()
		defer s.mu.Unlock()
		out := s.annotations[req.PathValue("image")]
		if out == nil {
			out = []Annotation{}
		}
		writeJSON(w, http.StatusOK, map[string]any{"results": out})
	})

	log.Fatal(http.ListenAndServe(":8104", mux))
}
```
:::

### 4-4. 同じ手順で動かすと何も残らない
同じ逆さまの座標を、今度は 1 回のリクエストで送ります。

```
$ curl -s -i -X POST localhost:8104/images/1/annotations \
    -d '{"boundingBox":{"bottomLeftPoint":{"x":10,"y":10},"topRightPoint":{"x":5,"y":5}},"notes":[{"content":"cat"}]}'
HTTP/1.1 400 Bad Request
Content-Type: text/plain; charset=utf-8

boundingBox.topRightPoint must be above and to the right of bottomLeftPoint

$ curl -s localhost:8104/images/1/annotations
{"results":[]}
```

400 の後に一覧を見ても、何も残っていません。
正しい座標で送ると、1 回のリクエストでノートまで入ったアノテーションができます。

```
$ curl -s -i -X POST localhost:8104/images/1/annotations \
    -d '{"boundingBox":{"bottomLeftPoint":{"x":5,"y":5},"topRightPoint":{"x":10,"y":10}},"notes":[{"content":"cat"}]}'
HTTP/1.1 200 OK
Content-Type: application/json

{"id":"1","boundingBox":{"bottomLeftPoint":{"x":5,"y":5},"topRightPoint":{"x":10,"y":10}},"notes":[{"content":"cat","createTime":"2026-10-28T07:12:40.022028Z"}]}

$ curl -s localhost:8104/images/1/annotations
{"results":[{"id":"1","boundingBox":{"bottomLeftPoint":{"x":5,"y":5},"topRightPoint":{"x":10,"y":10}},"notes":[{"content":"cat","createTime":"2026-10-28T07:12:40.022028Z"}]}]}
```

読む時も 1 回で、アノテーションの中身がそのまま返ります。

## 5. 1 リクエストの流れ
4-3 の作成リクエストがサーバーの中をどう通るかです。
送る側を利用者、受ける側をサーバーと呼びます。

1. 利用者が `POST /images/1/annotations` に、バウンディングボックスとノートを含めた JSON を送る
2. サーバーは JSON を `Annotation` に読む。読めなければ 400
3. バウンディングボックスの座標を検証し、ノートの `content` が空でないかを順に確かめる。どれか 1 つでも失敗したら 400 を返し、何も保存しない
4. ノートの `createTime` をサーバーの時刻で埋める
5. 画像ごとの一覧に追加し、id を付けたアノテーションを 200 で返す

4-1 では 3 が 3 つのリクエストに分かれていて、途中で止まると前のリクエストの結果だけが残ります。

## 6. 疑問と答え
読みながら引っかかったところです。

**リソースかデータ型かは何で決めるのか**
そのものを単独で作る・消す・取る必要があるかどうかです。
バウンディングボックスはアノテーションと 1 対 1 で、アノテーション抜きで扱うことがないのでデータ型にします。
ノートは個別に消したくなるかもしれませんが、小さくて数も増えないので、中に入れて丸ごと置き換える方が楽です。

**インラインにすると何が困るのか**
複数のリソースで共有されるデータを写してしまうことです。
著者の情報を本ごとに持つと、著者名が変わった時にすべての本を直すのかを利用者が判断することになります。
共有されるものは参照にして、1 か所に置きます。

**参照にすると呼び出しが 2 回になるのではないか**
なります。
管理者の名前を見るには、ChatRoom を取ってから User を取ることになります。
ただ、滅多に見ない情報を毎回インラインで返すと無視されるバイトを送り続けることになるので、よくある使い方の方に合わせます。

**階層にするかどうかは何で決めるのか**
親を消したら子も消えてほしいか、親にアクセスできる人は子にもアクセスできてほしいか、の 2 つです。
チャットルームとメッセージは両方当てはまるので階層にします。
子が複数の親を持ちうるなら、階層は向きません。

**階層が深いと何が困るのか**
ドキュメント 1 つを取るのに、大学・学校・コース・学期の 4 つの id を知っている必要があります。
しかも学校や学期を消すことはまず無いので、階層にした利点を使っていません。
書籍は、学校をコースのフィールドにして、学期はフィルタで絞る形に浅くしています。

**DB のテーブル設計と同じ感覚でよいのか**
書籍も、リレーショナル DB のスキーマを設計したことがあれば馴染みがあると書いています。
違うのは、API は利用者がやりたいことに合わせて形を決めるもので、保存の都合をそのまま見せるものではないことです。

ここまでを自分の言葉でまとめると、単独で扱うものだけをリソースにし、関係は目的に必要なものだけ持ち、階層は親子の振る舞いが欲しい時だけ使う、です。

## 7. トレードオフ
得られるのは、リソースとメソッドの数が減ること（4 リソース 20 メソッドが 2 リソース 10 メソッド）と、作成が 1 回のリクエストで終わって途中の状態が残らないことです。
引き換えに、中に入れたデータは単独で指せなくなります。
ノートを 1 つだけ消したければ、ノートのリストごと置き換えることになります。
インラインにした分だけ、レスポンスも大きくなります。

書籍は、よくある使い方に最適化して、高度な使い方ができなくならないようにする、という進め方を勧めています。
階層や参照は、後から付け足すより最初に決めておく方が、利用者のコードを壊さずに済みます。

## 8. 参考
- 『APIデザイン・パターン』JJ Geewax 著、マイナビ出版、第 4 章
- https://google.aip.dev/121 （リソース指向設計）
- https://google.aip.dev/124 （リソースの関連）
- 階層にしても「親を消したら子も消える」を提供しない例もあります。S3 のバケットとオブジェクトは階層ですが、`DeleteBucket` はバケットが空でないと失敗し、ドキュメントに「All objects (including all object versions and delete markers) in the bucket must be deleted before the bucket itself can be deleted.」とあります: https://docs.aws.amazon.com/AmazonS3/latest/API/API_DeleteBucket.html
