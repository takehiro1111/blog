---
title: "GoにおけるCORSの認可処理の実装パターン"
emoji: "📘"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Go", "CORS"]
published: true
---
![](/images/go/go_logo.png =450x)

## 本記事について
- GoにおけるCORSの実装を行います。
最終的にフロントエンドからCORSのリクエストが許可、拒否されていることを確認していきたいと思います。

## CORS(Cross-Origin Resource Sharing)とは？
- ブラウザのセキュリティ制限を緩和し、異なるオリジンからのリソースアクセスを許可するための仕組みです。
CORSの文脈におけるオリジンとは、プロトコル + ドメイン + ポート番号の組み合わせた文字列です。
例：https://example.com:443

この辺の記事が分かりやすいです。
https://qiita.com/Hirohana/items/9b5501c561954ad32be7

## CORSの認可実装パターン
今回はS3に画像ファイルを置いている前提で3つの実装についてパターン化しています。

### 1.フロントエンド -> S3( or 間にCDNを挟む)
- 以下のように認可はS3の責務となり、S3のCORS設定に一任されます。
CloudFrontのようなCDNを間に挟んでキャッシュを行いたい場合に採用する実装方式かと思います。
```json
{
  "CORSRules": [{
    "AllowedOrigins": ["https://example.com"],
    "AllowedMethods": ["GET", "PUT"],
    "AllowedHeaders": ["*"]
  }]
}
```




## コード

```go
func Cors(next http.Handler) http.Handler {
	allowedOrigins := strings.Split(os.Getenv("ALLOWED_ORIGINS"), ",")
	if len(allowedOrigins) == 0 {
			allowedOrigins = []string{"http://localhost:3001"} // デフォルト
	}

	c := cors.New(cors.Options{
		AllowedOrigins: allowedOrigins,
		AllowedMethods: []string{
			http.MethodGet,
			http.MethodPost,
			http.MethodPut,
			http.MethodPatch,
			http.MethodDelete,
			http.MethodOptions,
		},
		AllowedHeaders:   []string{"Content-Type", "X-Custom-Headers"},
		AllowCredentials: true,
		MaxAge:           3600,
		Debug:            os.Getenv("ENV") == "development",
	})
	return c.Handler(next)
}
```

## 参考
