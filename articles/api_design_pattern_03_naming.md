---
title: "[Go]APIデザインパターン 03: 名前付け（使う/使わないの前後比較）"
emoji: "📘"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Go", "API", "設計", "デザインパターン"]
published: false
---
![](/images/go/go_logo.png =450x)

## 本記事の内容
- 『APIデザイン・パターン』(JJ Geewax 著、マイナビ出版) の第 3 章「名前付け」を、Go で書き直しながら読んだメモです
- 原則に従わない名前と従う名前で同じ API を作り、同じ手順で動かして出力の違いを確かめます
- コードは Go 1.22 以降の `net/http` と標準ライブラリだけで動きます
- シリーズの目次は「[Go]APIデザインパターン 00: 目次と、パターンを使わないとどうなるか」にあります

## 1. 結論
API の名前は利用者のコードに埋め込まれるので、一度公開したら変えられないものとして決めます。
良い名前の条件は 3 つで、何を指すかが伝わること、余計な語が無いこと、他の名前から推測できることです。
この章で一番効くと感じたのは「同じ概念には同じ名前を使う」ことと「数値には単位を名前に入れる」ことでした。

第 3 章は書籍では「設計の原則」の部にあり、デザインパターンではありません。
それでも、従わない API と従う API を動かして比べると、違いははっきり出ます。

## 2. 困る場面
読んでいて最初に引っかかったのは、名前が悪いと具体的に何が起きるのか、自分の中に像がなかったことです。
書籍が挙げる事象は 2 種類あります。

1 つ目は、同じ概念に別の名前が付いている場合です。
あるメッセージでは `topic`、別のメッセージでは `messagingTopic` と呼ばれていると、利用者は片方を覚えてももう片方を推測できず、毎回ドキュメントを引くことになります。

2 つ目は、単位の無い名前です。
`size` というフィールドが、バイトなのか、秒なのか、ピクセルなのかは名前からは分かりません。
書籍は 1999 年のマーズ・クライメイト・オービターの事故を例に出しています。
片方のチームが重量ポンド秒で出した値を、もう片方のチームがニュートン秒として受け取り、必要な力の 4 倍以上がかかって探査機を失いました。
4-2 で、単位の無い名前のまま 2 つのメソッドをつないで、値が 4.45 倍ずれるところを見ます。

## 3. 足すもの
名前に足すのは、単位と一貫性です。
書籍が挙げる決め事を、私が使う順に並べます。

- 同じものには同じ名前を、違うものには違う名前を使います。`topic` と `messagingTopic` のような揺れを作りません
- 綴りはアメリカ英語にそろえます（`colour` ではなく `color`）
- メソッド名は命令形にします（`CreateBook`、`DeleteWeatherReading`）。`isValid()` のように問いかける形は何が返るかが曖昧なので、`GetValidationErrors()` のように返るものが分かる名前にします
- `with`、`to`、`for` のような前置詞が名前に入ったら、設計を疑います。`BookWithAuthor` が欲しくなった時に本当に必要なのは、第 8 章のフィールドマスクやビューです
- コレクション名は複数形、リソース名は単数形にします。`people` や `octopuses` のような不規則な複数形は辞書どおりにします
- 表記（キャメルケースなど）は 1 つ選んで通します。この記事では JSON のキーをキャメルケースにします
- `to`、`from`、`string` のような予約語は避け、`sender`、`recipient` のように具体的な語を使います
- 単位がある数値は、名前に単位を入れます（`sizeBytes`、`sizeMegapixels`）

単位を名前に入れる代わりに、専用の型で意味を持たせる方法もあります。
画像の縦横を `"1024x768"` という文字列で持つのではなく、`Dimensions` という型にします。

```go
type Image struct {
	Content    string     `json:"content"`    // ①
	SizeBytes  int64      `json:"sizeBytes"`  // ②
	Dimensions Dimensions `json:"dimensions"` // ③
}

type Dimensions struct {
	LengthPixels int64 `json:"lengthPixels"`
	WidthPixels  int64 `json:"widthPixels"`
}
```

- ① Base64 でエンコードした画像の中身です
- ② 単位がバイトだと名前で分かります
- ③ `dimensions` 自体に単位はありませんが、`Dimensions` 型の中のフィールド名がピクセルだと教えてくれます

:::message
利用者が見るのは Go の struct のフィールド名ではなく、`json:"sizeBytes"` のタグに書いた名前です。
API の名前として決めるのはタグの方で、Go 側の `SizeBytes` はサーバーの中だけの名前です。
:::

## 4. 前後比較
### 4-1. 使わない場合
書籍の 3.6 節にある、探査機の計算 API です。
力積を計算するメソッドと、その力積から軌道変更を計算するメソッドが、別々のチームで作られています。

```go
type CalculateImpulseRequest struct {
	Thrust       float64 `json:"thrust"`
	BurnDuration float64 `json:"burnDuration"`
}

type CalculateImpulseResponse struct {
	Impulse float64 `json:"impulse"` // ①
}

type CalculateManeuverRequest struct {
	Impulse float64 `json:"impulse"` // ②
	Mass    float64 `json:"mass"`
}

type CalculateManeuverResponse struct {
	DeltaVelocity float64 `json:"deltaVelocity"`
}

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("POST /impulse:calculate", func(w http.ResponseWriter, req *http.Request) {
		var in CalculateImpulseRequest
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, http.StatusOK, CalculateImpulseResponse{Impulse: in.Thrust * in.BurnDuration}) // ③
	})

	mux.HandleFunc("POST /maneuver:calculate", func(w http.ResponseWriter, req *http.Request) {
		var in CalculateManeuverRequest
		if err := json.NewDecoder(req.Body).Decode(&in); err != nil {
			http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
			return
		}
		if in.Mass <= 0 {
			http.Error(w, "mass must be positive", http.StatusBadRequest)
			return
		}
		writeJSON(w, http.StatusOK, CalculateManeuverResponse{DeltaVelocity: in.Impulse / in.Mass}) // ④
	})

	log.Fatal(http.ListenAndServe(":8003", mux))
}
```

- ① このチームは重量ポンドと秒で計算するので、`impulse` は重量ポンド秒です
- ② こちらのチームは SI 単位で計算するので、`impulse` はニュートン秒のつもりです
- ③ 推力 × 噴射時間です
- ④ 力積 ÷ 質量で速度の変化を出します

同じ `impulse` という名前なのに、単位が違います。
名前からはそれが分かりません。

### 4-2. 動かすと値が 4.45 倍ずれる
1 つ目のメソッドの出力を、そのまま 2 つ目のメソッドに渡します。

```
$ curl -s -i -X POST localhost:8003/impulse:calculate \
    -d '{"thrust":100,"burnDuration":10}'
HTTP/1.1 200 OK
Content-Type: application/json

{"impulse":1000}

$ curl -s -i -X POST localhost:8003/maneuver:calculate \
    -d '{"impulse":1000,"mass":100}'
HTTP/1.1 200 OK
Content-Type: application/json

{"deltaVelocity":10}
```

エラーは出ません。
1000 重量ポンド秒は約 4448.2 ニュートン秒なので、正しい答えは 44.482 です。
返ってきた 10 は 4.45 倍小さい値ですが、サーバーも利用者も気付けません。

### 4-3. 使う場合（差分）
フィールド名に単位を入れます。
合わせて、定義に無いフィールド名で送られてきたら 400 Bad Request で断るようにします。

```diff go
 type CalculateImpulseRequest struct {
-	Thrust       float64 `json:"thrust"`
-	BurnDuration float64 `json:"burnDuration"`
+	ThrustPoundsForce float64 `json:"thrustPoundsForce"`
+	BurnSeconds       float64 `json:"burnSeconds"`
 }

 type CalculateImpulseResponse struct {
-	Impulse float64 `json:"impulse"`
+	ImpulsePoundForceSeconds float64 `json:"impulsePoundForceSeconds"` // ①
 }

 type CalculateManeuverRequest struct {
-	Impulse float64 `json:"impulse"`
-	Mass    float64 `json:"mass"`
+	ImpulseNewtonSeconds float64 `json:"impulseNewtonSeconds"` // ②
+	MassKilograms        float64 `json:"massKilograms"`
 }

 type CalculateManeuverResponse struct {
-	DeltaVelocity float64 `json:"deltaVelocity"`
+	DeltaVelocityMetersPerSecond float64 `json:"deltaVelocityMetersPerSecond"`
 }
+
+func decodeStrict(r io.Reader, v any) error {
+	dec := json.NewDecoder(r)
+	dec.DisallowUnknownFields() // ③
+	return dec.Decode(v)
+}
```

ハンドラ側は、`json.NewDecoder(req.Body).Decode(&in)` を `decodeStrict(req.Body, &in)` に替えるだけです。

- ① 出力の単位が名前で分かります
- ② 入力の単位も名前で分かります。①と名前が違うので、そのまま渡せないことに利用者が気付けます
- ③ 定義に無いフィールド名が来たらエラーにします

:::message
`encoding/json` は、struct に無いキーを黙って捨てます。
名前を直しただけだと、古い名前で送ってきた利用者には `impulseNewtonSeconds` にゼロ値の 0 が入ったまま計算が進んでしまうので、`DisallowUnknownFields` で止めています。
:::

書籍が名前を変えているのは `impulse` の 2 つだけです。
この記事では入力側の `thrust`、`burnDuration`、`mass` にも単位を付けました。

:::details after/main.go の全文
```go
package main

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
)

type CalculateImpulseRequest struct {
	ThrustPoundsForce float64 `json:"thrustPoundsForce"`
	BurnSeconds       float64 `json:"burnSeconds"`
}

type CalculateImpulseResponse struct {
	ImpulsePoundForceSeconds float64 `json:"impulsePoundForceSeconds"` // ①
}

type CalculateManeuverRequest struct {
	ImpulseNewtonSeconds float64 `json:"impulseNewtonSeconds"` // ②
	MassKilograms        float64 `json:"massKilograms"`
}

type CalculateManeuverResponse struct {
	DeltaVelocityMetersPerSecond float64 `json:"deltaVelocityMetersPerSecond"`
}

func decodeStrict(r io.Reader, v any) error {
	dec := json.NewDecoder(r)
	dec.DisallowUnknownFields() // ③
	return dec.Decode(v)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("POST /impulse:calculate", func(w http.ResponseWriter, req *http.Request) {
		var in CalculateImpulseRequest
		if err := decodeStrict(req.Body, &in); err != nil {
			http.Error(w, "invalid request: "+err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, http.StatusOK, CalculateImpulseResponse{ImpulsePoundForceSeconds: in.ThrustPoundsForce * in.BurnSeconds})
	})

	mux.HandleFunc("POST /maneuver:calculate", func(w http.ResponseWriter, req *http.Request) {
		var in CalculateManeuverRequest
		if err := decodeStrict(req.Body, &in); err != nil {
			http.Error(w, "invalid request: "+err.Error(), http.StatusBadRequest)
			return
		}
		if in.MassKilograms <= 0 {
			http.Error(w, "massKilograms must be positive", http.StatusBadRequest)
			return
		}
		writeJSON(w, http.StatusOK, CalculateManeuverResponse{DeltaVelocityMetersPerSecond: in.ImpulseNewtonSeconds / in.MassKilograms})
	})

	log.Fatal(http.ListenAndServe(":8103", mux))
}
```
:::

### 4-4. 同じ手順で動かすと 400 で止まる
4-2 と同じ手順です。
1 つ目の出力を、名前を変えずに 2 つ目へ渡してみます。

```
$ curl -s -i -X POST localhost:8103/impulse:calculate \
    -d '{"thrustPoundsForce":100,"burnSeconds":10}'
HTTP/1.1 200 OK
Content-Type: application/json

{"impulsePoundForceSeconds":1000}

$ curl -s -i -X POST localhost:8103/maneuver:calculate \
    -d '{"impulse":1000,"mass":100}'
HTTP/1.1 400 Bad Request
Content-Type: text/plain; charset=utf-8

invalid request: json: unknown field "impulse"
```

`impulsePoundForceSeconds` を `impulseNewtonSeconds` に渡すには換算が要る、と名前が教えてくれます。
4.4482 を掛けて送り直すと、正しい値が返ります。

```
$ curl -s -i -X POST localhost:8103/maneuver:calculate \
    -d '{"impulseNewtonSeconds":4448.2,"massKilograms":100}'
HTTP/1.1 200 OK
Content-Type: application/json

{"deltaVelocityMetersPerSecond":44.482}
```

## 5. 1 リクエストの流れ
名前が効くのは、利用者が 2 つ目のリクエストを組み立てる場面です。
利用者とサーバーの間で何が起きるかを順に追います。

1. 利用者が `POST /impulse:calculate` を送り、`impulsePoundForceSeconds: 1000` を受け取る
2. 利用者は `POST /maneuver:calculate` の定義を見る。フィールド名が `impulseNewtonSeconds` なので、受け取った値をそのまま入れられないと分かり、4.4482 を掛ける
3. サーバーは本文を `CalculateManeuverRequest` に読む。定義に無いキーがあれば 400 を返す
4. `massKilograms` が正の数かを確かめ、割り算して `deltaVelocityMetersPerSecond` を返す

4-1 の API では 2 の判断が起きません。
名前が同じなので、利用者は何も考えずに値を渡します。

## 6. 疑問と答え
読みながら引っかかったところです。

**名前が悪いと分かった時点で直せばよいのではないか**
公開した名前は利用者のコードに書かれていて、こちらからは直せません。
自分のコードの関数名なら検索置換で済みますが、API では手の届かない利用者のコードが必ず残ります。
名前を変える手順は、第 24 章の互換性の話になります。

**`topic` と `messagingTopic` はどちらが正しいのか**
どちらでも構いません。
大事なのは 1 つに決めて API 全体で使い続けることで、違う名前を使うなら違う概念を指していなければなりません。

**前置詞が入った名前の何がまずいのか**
`BookWithAuthor` は「Author も一緒に返してほしい」という要望を、新しいリソース名で解決しています。
Publisher も一緒に欲しい、両方欲しい、となると組み合わせの数だけメソッドが増えます。
前置詞は、別の仕組みで解くべき問題が名前に漏れ出している印です。

**`pageSize` と `maxPageSize` は何が違うのか**
`pageSize: 10` は「10 件ください」と読めますが、サーバーが約束できるのは最大 10 件です。
8 件返ってきた利用者は「もう無い」と思ってページングをやめ、残りを取りこぼします。
`maxPageSize` なら最初から「最大 10 件」と読めるので、この誤解が起きません。

**すべてのフィールドに単位を付けるべきか**
単位があるものだけです。
`firstName` に単位はありません。
縦と横のように複数の数値からなる値は、`"1024x768"` という文字列にせず、`Dimensions` のような型にして型に意味を持たせます。

ここまでを自分の言葉でまとめると、名前は変えられない前提で決めるもので、同じ概念には同じ名前を、数値には単位を付けて、利用者が片方を覚えればもう片方を推測できるようにする、です。

## 7. トレードオフ
得られるのは、利用者がドキュメントを引き直さずに次のフィールド名を推測できることと、単位の取り違えが実行前に見つかることです。
引き換えに、名前は長くなります。
`impulsePoundForceSeconds` は `impulse` の 3 倍の長さで、表記や複数形のような決め事も最初に揃えておく必要があります。

前置詞を避ける方針は、名前の修正では済まず、フィールドマスクのような別の設計を持ち込むことになる場合があります。
書籍は、迷ったら何かを 1 つ選んで一貫して使い、前置詞が出てきたら設計を見直す合図と受け取る、という進め方を勧めています。

## 8. 参考
- 『APIデザイン・パターン』JJ Geewax 著、マイナビ出版、第 3 章
- https://google.aip.dev/140 （フィールド名）
- https://google.aip.dev/190 （命名規則）
- AWS にも単位の無い名前はあります。EC2 の `CreateVolume` の `Size` は名前に単位が無く、ドキュメントの「The size of the volume, in GiBs.」で初めて GiB だと分かります: https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_CreateVolume.html
