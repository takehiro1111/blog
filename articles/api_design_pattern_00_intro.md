---
title: "[Go]APIデザインパターン 00: 目次と、パターンを使わないとどうなるか"
emoji: "📘"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Go", "API", "設計", "デザインパターン"]
published: false
---
![](/images/go/go_logo.png =450x)

## 本記事の内容
- 『APIデザイン・パターン』(JJ Geewax 著、マイナビ出版、2022) を Go で書き直しながら読んだシリーズの入口です
- 第 1 章と第 2 章の内容（この本で言うデザインパターンとは何か、なぜ API では特に効くのか）と、第 3 章以降の記事の目次をまとめます
- 第 2 章のケーススタディ（Twitter 風の API）を Go で動かして、パターンを最初から使わないと何が起きるかを出力で確かめます

## 1. なぜこの本を Go で読み直すのか
私はインフラや SRE の仕事が主で、API の設計は「なんとなく REST らしく」で済ませてきました。
Go でバックエンドを書くようになって、リソースの切り方、識別子、ページ分割、再試行のような判断を毎回その場で決めているのが気になり、この本を読みました。

本の例は TypeScript 風のインターフェース定義だけで、動く実装はありません。
そこで章ごとに Go で「パターンを使わない実装」と「使う実装」を書き、同じリクエストを送って何が変わるかを出力で確かめることにしました。

## 2. この本で言う「デザインパターン」
ソフトウェアのデザインパターンは、同じ形の問題に繰り返し使える設計の青写真です。
API のデザインパターンは、それを API のインターフェース（リソースの構造とメソッド）に当てはめたもので、実装の中身までは決めません。
ただし「このメソッドの結果は少し古いことがある」のように、振る舞いの一部を決めることはあります（2.1）。

### なぜ API では特に大事なのか
本は、インターフェースを「柔軟か硬直か」と「非公開か公開か」の 2 軸で見ます。
GUI はボタンの位置が変わっても人が対応できるので柔軟です。
API はフィールド名を 1 つ変えただけで利用者のコードが壊れるので硬直しています。
さらに公開 API は利用者が世界中にいるので、「作ってから直す」が最も難しい組み合わせになります（2.2）。

| 柔軟性 | 利用者 | 例 | 変更の難しさ |
|---|---|---|---|
| 柔軟 | 非公開 | 社内の監視画面 | とても簡単 |
| 柔軟 | 公開 | Web サイトの画面 | 中くらい |
| 硬直 | 非公開 | 社内向け API | 難しい |
| 硬直 | 公開 | 公開 API | とても難しい |

だから API は、後から反復して直すのではなく、最初から実績のある形で作る価値が他のソフトウェアより大きい、というのがこの本の出発点です。

## 3. 良い API の 4 つの条件
第 1 章は「良い API とは何か」を 4 つに分けています（1.4）。

- 実行可能であること。利用者がやりたいことが実際にできて、遅延や精度のような要件も満たしている
- 表現力があること。やりたいことを明確に表せるメソッドがある。言語判定をしたいのに、翻訳 API を全言語分呼んで推測するような回避策を利用者にさせない
- シンプルであること。メソッド数を減らすことではなく、よく使う機能を簡単に、高度な機能も可能にすること。`targetLanguage` だけでも、`modelId` を足しても呼べる翻訳メソッドが本の例です
- 予測可能であること。あるメッセージで `text` だったフィールドが、別のメッセージで `inputText` になっていない。利用者はドキュメントを全部読まず、知っている形から推測します

シリーズの各記事では、この 4 つのうち主に「予測可能であること」が、パターンに従う理由として繰り返し出てきます。

## 4. リソース指向と標準メソッド
本の API はすべてリソース指向です（1.3）。
操作ごとに `ScheduleFlight()` や `CancelReservation()` のような名前を考えるのではなく、先に「リソース」を決めて、それに標準メソッドを当てはめます。

| 標準メソッド | 意味 |
|---|---|
| Create | 新しいリソースを作る |
| Get | 1 件取得する |
| List | 一覧を取得する |
| Update | 更新する |
| Delete | 削除する |

`FlightReservation` というリソースを 1 つ決めれば、`CreateFlightReservation()` から `DeleteFlightReservation()` までの 5 つが自動的に決まります。
標準メソッドを 5 つ覚えていれば、新しいリソースを 1 つ覚えるだけで 5 つのメソッドが推測できる、というのが利点です。
HTTP との対応や細かい決まりは、第 7 章の記事で扱います。

## 5. パターンを使わないとどうなるか（第 2 章のケーススタディ）
第 2 章の後半は、Twitter 風の API（本では Twapi）を題材に、パターンを使わずに作り始めると何が起きるかを見せています（2.4）。
ここだけ Go で動かしました。

### 5-1. 使わない場合
ユーザーのメッセージ一覧を返すだけのメソッドです。
サーバーには 1,000 件のメッセージを入れておきます。

```go
type ListMessagesResponse struct {
	Results []Message `json:"results"`
}

mux.HandleFunc("GET /users/{userId}/messages", func(w http.ResponseWriter, req *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(ListMessagesResponse{Results: messages[req.PathValue("userId")]}) // ①
})
```

- ① 持っているメッセージを全部、1 回のレスポンスに入れます

利用者の側には、この API 向けに「全件を受け取って like 数の平均を出す」コードがあるとします。

```go
var out ListMessagesResponse
json.NewDecoder(resp.Body).Decode(&out)
total := 0
for _, m := range out.Results { // ①
	total += m.Likes
}
fmt.Printf("count=%d average_likes=%.2f\n", len(out.Results), float64(total)/float64(len(out.Results)))
```

- ① `results` に全件入っている前提で合計します

### 5-2. 動かすと 1 レスポンスが 46KB になる
```
$ curl -s localhost:8002/users/1/messages | wc -c
   46800

$ ./client http://localhost:8002/users/1/messages
count=1000 average_likes=3.00
```

1,000 件で 46KB です。
本が挙げている例では 50 万件で 70MB になり、API サーバーも利用者も扱えなくなります。
最初は正しく動くので、問題に気付くのは件数が増えてからです。

### 5-3. 後からページ分割を足す（差分）
件数が増えてから、ページ分割パターン（第 21 章）を足します。
リクエストに `maxPageSize` と `pageToken`、レスポンスに `nextPageToken` が増えます。

```diff go
 type ListMessagesResponse struct {
-	Results []Message `json:"results"`
+	Results       []Message `json:"results"`
+	NextPageToken string    `json:"nextPageToken,omitempty"` // ①
 }

 mux.HandleFunc("GET /users/{userId}/messages", func(w http.ResponseWriter, req *http.Request) {
-	w.Header().Set("Content-Type", "application/json")
-	json.NewEncoder(w).Encode(ListMessagesResponse{Results: messages[req.PathValue("userId")]})
+	all := messages[req.PathValue("userId")]
+	size := 100 // ②
+	if v := req.URL.Query().Get("maxPageSize"); v != "" {
+		n, err := strconv.Atoi(v)
+		if err != nil || n <= 0 {
+			http.Error(w, "maxPageSize must be a positive integer", http.StatusBadRequest)
+			return
+		}
+		if n < size {
+			size = n
+		}
+	}
+	start, err := decodeToken(req.URL.Query().Get("pageToken")) // ③
+	if err != nil || start < 0 || start > len(all) {
+		http.Error(w, "invalid pageToken", http.StatusBadRequest)
+		return
+	}
+	end := start + size
+	if end > len(all) {
+		end = len(all)
+	}
+	resp := ListMessagesResponse{Results: all[start:end]}
+	if end < len(all) {
+		resp.NextPageToken = encodeToken(end) // ④
+	}
+	w.Header().Set("Content-Type", "application/json")
+	json.NewEncoder(w).Encode(resp)
 })
```

- ① 次のページがある時だけ入ります。最後のページでは省略されます
- ② 1 ページの上限です。`maxPageSize` は、これより小さい値を指定した時だけ効きます
- ③ `pageToken` は、利用者には意味の分からない文字列として扱ってもらいます。ここでは開始位置を base64 にしただけです
- ④ 次のページを取るためのトークンを返します

:::details after/main.go の全文
```go
package main

import (
	"encoding/base64"
	"encoding/json"
	"log"
	"net/http"
	"strconv"
)

type Message struct {
	ID      string `json:"id"`
	Content string `json:"content"`
	Likes   int    `json:"likes"`
}

type ListMessagesResponse struct {
	Results       []Message `json:"results"`
	NextPageToken string    `json:"nextPageToken,omitempty"`
}

func seed(n int) []Message {
	msgs := make([]Message, 0, n)
	for i := 1; i <= n; i++ {
		msgs = append(msgs, Message{ID: strconv.Itoa(i), Content: "message " + strconv.Itoa(i), Likes: i % 7})
	}
	return msgs
}

func decodeToken(t string) (int, error) {
	if t == "" {
		return 0, nil
	}
	b, err := base64.URLEncoding.DecodeString(t)
	if err != nil {
		return 0, err
	}
	return strconv.Atoi(string(b))
}

func encodeToken(offset int) string {
	return base64.URLEncoding.EncodeToString([]byte(strconv.Itoa(offset)))
}

func main() {
	messages := map[string][]Message{"1": seed(1000)}
	mux := http.NewServeMux()

	mux.HandleFunc("GET /users/{userId}/messages", func(w http.ResponseWriter, req *http.Request) {
		all := messages[req.PathValue("userId")]
		size := 100
		if v := req.URL.Query().Get("maxPageSize"); v != "" {
			n, err := strconv.Atoi(v)
			if err != nil || n <= 0 {
				http.Error(w, "maxPageSize must be a positive integer", http.StatusBadRequest)
				return
			}
			if n < size {
				size = n
			}
		}
		start, err := decodeToken(req.URL.Query().Get("pageToken"))
		if err != nil || start < 0 || start > len(all) {
			http.Error(w, "invalid pageToken", http.StatusBadRequest)
			return
		}
		end := start + size
		if end > len(all) {
			end = len(all)
		}
		resp := ListMessagesResponse{Results: all[start:end]}
		if end < len(all) {
			resp.NextPageToken = encodeToken(end)
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	})

	log.Fatal(http.ListenAndServe(":8102", mux))
}
```
:::

### 5-4. 同じ手順で動かすと、古い利用者が気付かずに間違える
新しい形では、2 件ずつ取れます。

```
$ curl -s 'localhost:8102/users/1/message			s?maxPageSize=2'
{"results":[{"id":"1","content":"message 1","likes":1},{"id":"2","content":"message 2","likes":2}],"nextPageToken":"Mg=="}

$ curl -s 'localhost:8102/users/1/messages?maxPageSize=2&pageToken=Mg=='
{"results":[{"id":"3","content":"message 3","likes":3},{"id":"4","content":"message 4","likes":4}],"nextPageToken":"NA=="}
```

問題は、変更前に書かれた利用者のコードです。
5-1 の平均を出すコードを、そのまま新しいサーバーに向けるとこうなります。

```
$ ./client http://localhost:8102/users/1/messages
count=100 average_likes=2.97
```

エラーは出ません。
`results` には最初の 100 件だけが入り、`nextPageToken` は読まれないので、利用者は 100 件が全件だと思って平均を出します。
1,000 件の平均 3.00 が 2.97 になっただけなので、気付くのは相当後です。
本が「最初からパターンを使う理由」として挙げているのが、この「壊れずに間違う」事象です。

### 5-5. エクスポートの例
本はもう 1 つ、メッセージを別のストレージに書き出すメソッドでも同じ比較をしています。
こちらは第 10 章（ロングランオペレーション）と第 23 章（インポートとエクスポート）の記事で動かすので、ここでは形だけ Go にしておきます。

```go
// 使わない場合: 圧縮ファイルの URL を返すだけ
type ExportMessagesResponse struct {
	ExportDownloadURI string `json:"exportDownloadUri"`
}

// 使う場合: 送り先と設定を受け取り、進捗を追える Operation を返す
type ExportMessagesRequest struct {
	Parent       string              `json:"parent"`
	OutputConfig MessageOutputConfig `json:"outputConfig"`
}

type MessageOutputConfig struct {
	Destination       Destination        `json:"destination"`
	CompressionConfig *CompressionConfig `json:"compressionConfig,omitempty"`
	EncryptionConfig  *EncryptionConfig  `json:"encryptionConfig,omitempty"`
}

type Operation[R, M any] struct {
	ID       string          `json:"id"`
	Done     bool            `json:"done"`
	Result   *R              `json:"result,omitempty"`
	Error    *OperationError `json:"error,omitempty"`
	Metadata *M              `json:"metadata,omitempty"`
}
```

URL を返すだけの形だと、送り先を S3 にしたい、圧縮方式を選びたい、進捗を見たい、途中でやめたい、のどれも後から足せません。
足そうとするとレスポンスの形が変わり、既存の利用者が壊れます。

## 6. 各パターンの記事の読み方
本の各章は、名前と概要、対象とする問題、概要、実装、トレードオフ、の順で書かれています（2.3）。
シリーズの記事もこれに合わせて、次の見出しで統一しました。

1. 結論。どこに何を足すと、何が起きなくなるか
2. 困る場面。パターンが無いと何が起きるか
3. 足すもの。フィールド、メソッド、ステータスコード
4. 前後比較。使わない実装と使う実装を Go で動かして、同じ手順の出力を並べる
5. 1 リクエストの流れ。本番でリクエストがサーバーの中をどう通るか
6. 疑問と答え。読みながら引っかかったところ
7. トレードオフ。引き換えに失うもの
8. 参考。本の章、Google の AIP、AWS に同じ仕組みがあればその名前

Go のコードは、Go 1.22 以降の `net/http` と標準ライブラリだけで動くようにしています。

## 7. 目次
本の構成どおりに並べます。
リンクは公開したものから順に有効になります。

### 設計の原則（第 2 部）
- [03 名前付け](https://zenn.dev/takehiro1111/articles/api_design_pattern_03_naming)
- [04 リソースの範囲と階層](https://zenn.dev/takehiro1111/articles/api_design_pattern_04_resource_layout)
- [05 データ型とデフォルト値](https://zenn.dev/takehiro1111/articles/api_design_pattern_05_data_types)

### 基礎編（第 3 部）
- [06 リソース識別子](https://zenn.dev/takehiro1111/articles/api_design_pattern_06_resource_id)
- [07 標準メソッド](https://zenn.dev/takehiro1111/articles/api_design_pattern_07_standard_methods)
- [08 部分的な更新と取り出し](https://zenn.dev/takehiro1111/articles/api_design_pattern_08_partial_update)
- [09 カスタムメソッド](https://zenn.dev/takehiro1111/articles/api_design_pattern_09_custom_methods)
- [10 ロングランオペレーション](https://zenn.dev/takehiro1111/articles/api_design_pattern_10_lro)
- [11 再実行可能ジョブ](https://zenn.dev/takehiro1111/articles/api_design_pattern_11_rerunnable_jobs)

### リソース間の関係（第 4 部）
- [12 シングルトンサブリソース](https://zenn.dev/takehiro1111/articles/api_design_pattern_12_singleton_sub)
- [13 相互参照](https://zenn.dev/takehiro1111/articles/api_design_pattern_13_cross_reference)
- [14 アソシエーションリソース](https://zenn.dev/takehiro1111/articles/api_design_pattern_14_association)
- [15 カスタムメソッド add / remove](https://zenn.dev/takehiro1111/articles/api_design_pattern_15_add_remove)
- [16 ポリモーフィズム](https://zenn.dev/takehiro1111/articles/api_design_pattern_16_polymorphism)

### コレクションの操作（第 5 部）
- [17 コピーと移動](https://zenn.dev/takehiro1111/articles/api_design_pattern_17_copy_move)
- [18 バッチ操作](https://zenn.dev/takehiro1111/articles/api_design_pattern_18_batch)
- [19 条件に基づく削除](https://zenn.dev/takehiro1111/articles/api_design_pattern_19_purge)
- [20 匿名書き込み](https://zenn.dev/takehiro1111/articles/api_design_pattern_20_anonymous_write)
- [21 ページ分割](https://zenn.dev/takehiro1111/articles/api_design_pattern_21_pagination)
- [22 フィルタリング](https://zenn.dev/takehiro1111/articles/api_design_pattern_22_filtering)
- [23 インポートとエクスポート](https://zenn.dev/takehiro1111/articles/api_design_pattern_23_import_export)

### 安心と安全（第 6 部）
- [24 バージョン管理と互換性](https://zenn.dev/takehiro1111/articles/api_design_pattern_24_versioning)
- [25 論理削除](https://zenn.dev/takehiro1111/articles/api_design_pattern_25_soft_delete)
- [26 リクエストの重複実行回避](https://zenn.dev/takehiro1111/articles/api_design_pattern_26_request_dedup)
- [27 リクエストの検証](https://zenn.dev/takehiro1111/articles/api_design_pattern_27_validation)
- [28 リソースリビジョン](https://zenn.dev/takehiro1111/articles/api_design_pattern_28_revisions)
- [29 リクエストの再試行](https://zenn.dev/takehiro1111/articles/api_design_pattern_29_retry)
- [30 リクエストの認証](https://zenn.dev/takehiro1111/articles/api_design_pattern_30_authentication)

### 読む順番
全部を順に読む必要はありません。
私は、まず 06・07・21 で「リソース、標準メソッド、ページ分割」の土台を作り、次に 26 と 29 で「失敗した時に何が起きるか」を押さえてから、残りは必要になった時に読む、という順にしました。

## 8. 参考
- 『APIデザイン・パターン』JJ Geewax 著、マイナビ出版、2022（原著 "API Design Patterns", Manning, 2021）
- Google の API 設計ガイド AIP: https://google.aip.dev/
- 著者が Google のルールを体系化したものが AIP で、本はそのルールの「理由」を書いたもの、と本の「はじめに」にあります
