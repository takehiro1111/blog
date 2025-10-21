---
title: "Go/Ginでslogを使ったロギングのミドルウェア実装"
emoji: "📝"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Go","Gin", "slog"]
published: true
---

# 1.記事を書いた背景
- 自分の整理用とこんな書き方もあるんだ程度に参考になればと思い記事に起こしています。
	- 当初はレベルや出力先のみ指定してパスくらい表示するよう実装しようと思っていましたが、実装を進める中で変なスイッチも入り、様々な機能を追加していきました。結果的に実用的なミドルウェアとして、リクエストボディのマスキングや分散トレーシングのためのリクエストID生成など、本番環境での使用を一定想定した機能を実装しています。


# 2.機能要件
```md
- ミドルウェアとして実装してラップすることで全てのエンドポイントに適用できる。
- 時刻等の可変性のある設定については、依存性を注入し実装すること。
  - テストコードでMockを使用したいため。
- パフォーマンスを図る指標として、レスポンスの際にレイテンシーも取得すること。
- エンドポイントによってはログを残さないよう設定できること。
- 予め指定したリクエストボディの値はマスク出来るようにする
- リクエストボディのMaxのサイズを指定できる
  - Maxサイズを超過するデータはログに記録されない。
  - ログの肥大化を防ぐための設定で、エラーにならず後続のハンドラーはボディを受け取ることができる。
- 分散トレーシングのためにリクエストIDを振り分ける。
- ステータスコードに応じてログのレベルを動的に設定できる
```

# 3.ログのフォーマット
  - Request
  ```zsh
  GET level=INFO msg=[Req] method=GET path=/test query="" ip=::1 user_agent=curl/8.7.1 request_id=d35c5885-3a17-4867-b0f7-ff21f2d909ec
  POST level=INFO msg=[Req] method=POST path=/api/v1/users query="" ip=::1 user_agent=curl/8.7.1 request_id=d37150b7-5e63-4421-bf6c-6615efbe2030 request_body="{\"email\":\"john@example.com\",\"username\":\"john\"}"
  ```
    

  - Response
  ```zsh
  GET level=INFO msg=[Res] method=GET path=/test query="" status=200 latency=0.58ms ip=::1 response_size=13 request_id=d35c5885-3a17-4867-b0f7-ff21f2d909ec
  POST level=WARN msg=[Res] method=POST path=/api/v1/users query="" status=404 latency=0.13ms ip=::1 response_size=-1 request_id=d37150b7-5e63-4421-bf6c-6615efbe2030
  ```
### 実行結果
- コード長いので最初に結果を表示します。

#### curlによるリクエスト
```zsh
curl localhost:8080/test
{"test":"OK"}%

curl localhost:8080/test2
{"test2":"OK"}%

curl -X POST http://localhost:8080/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{"username":"john","email":"john@example.com"}'
404 page not found%

```

#### `os.Stdout`で標準出力に設定しているためターミナルにログが出力される
```shell
air

  __    _   ___
 / /\  | | | |_)
/_/--\ |_| |_| \_ v1.63.0, built with Go go1.25.1

watching .
!exclude tmp
building...
running...

# GET /test
time=2025-10-21T15:43:26.971+09:00 level=INFO msg=[Req] method=GET path=/test query="" ip=::1 user_agent=curl/8.7.1 request_id=bbfcab14-f074-4666-9908-d46453332262
time=2025-10-21T15:43:26.971+09:00 level=INFO msg=[Res] method=GET path=/test query="" status=200 latency=0.46ms ip=::1 response_size=13 request_id=bbfcab14-f074-4666-9908-d46453332262
[GIN] 2025/10/21 - 15:43:26 | 200 |     475.167µs |             ::1 | GET      "/test"

# GET /test2
# ログを残さないよう意図的に除外設定を入れているため、表示されない。
[GIN] 2025/10/21 - 15:43:29 | 200 |      18.375µs |             ::1 | GET      "/test2"

# POST /users 
# そんなエンドポイントはhandler側で設定してないぞ！ということで`404`になっている。
# 4xx系はWARNで表示されることを確認。
time=2025-10-21T15:43:36.093+09:00 level=INFO msg=[Req] method=POST path=/api/v1/users query="" ip=::1 user_agent=curl/8.7.1 request_id=1695b81a-1c21-4bf9-a604-b015302682f7 request_body="{\"email\":\"john@example.com\",\"username\":\"john\"}"
time=2025-10-21T15:43:36.093+09:00 level=WARN msg=[Res] method=POST path=/api/v1/users query="" status=404 latency=0.09ms ip=::1 response_size=-1 request_id=1695b81a-1c21-4bf9-a604-b015302682f7
[GIN] 2025/10/21 - 15:43:36 | 404 |     102.792µs |             ::1 | POST     "/api/v1/users"
```

# 4.実装内容
## 4-1.ディレクトリ構造
- 今回はGin専用のMiddlewareで内部的にしか使用しないパッケージとして作成したいため、以下を参考にルートで`/internal`を切って、その配下で実装しました。
https://github.com/golang-standards/project-layout

- プロジェクト配下にある`tmp`はairを実行した際に動的に作成されるため気にせずでOK！
- 今回の記事ではテストは記述していません。
```zsh
├── go.mod
├── go.sum
├── internal
│   └── middleware
│       ├── logger_test.go
│       └── logger.go
├── README.md
├── {project_dir}
│   ├── main.go
│   └── tmp
│       └── main

```

## 4-2.logger.go
### Middlewareのメインの処理

:::details LoggerMiddleware

```go
package middleware

import (
	"bytes"
	"encoding/json"
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"io"
	"log/slog"
	"os"
	"strings"
	"time"
)

func LoggerMiddleware(loggerConfig *LoggerConfig) gin.HandlerFunc {
	slogger := NewLogger(loggerConfig)

	return func(c *gin.Context) {
		// スキップ対象パスに設定済みのエンドポイントはログを出力しない
		if shouldSkip(c.Request.URL.Path, loggerConfig.SkipPaths) {
			c.Next()
			return
		}

		start := loggerConfig.TimeNow()
		path := c.Request.URL.Path
		query := c.Request.URL.RawQuery

		// 分散トレーシングのためのリクエストIDの取得 or デフォルト値設定
		requestID := c.GetHeader("X-Request-ID")
		if requestID == "" {
			// クライアントが渡していない場合は自動生成
			requestID = loggerConfig.UUIDGen.Generate()
			c.Set("request_id", requestID) // 後続のハンドラで使えるようにセット
		}

		var requestBody string
		if loggerConfig.EnableRequestBody {
			contentType := c.GetHeader("Content-Type")
			if shouldLogBody(contentType) {
				// ボディを指定した最大サイズまで読み取り
				bodyBytes, err := io.ReadAll(io.LimitReader(c.Request.Body, loggerConfig.MaxBodyLogSize))
				if err == nil && len(bodyBytes) > 0 {
					// ボディを復元(後続のhandlerのため。)
					c.Request.Body = io.NopCloser(bytes.NewBuffer(bodyBytes))

					// マスキング処理
					requestBody = maskSensitiveData(string(bodyBytes))
				}
			}
		}

		reqFields := []any{
			slog.String("method", c.Request.Method),
			slog.String("path", path),
			slog.String("query", query),
			slog.String("ip", c.ClientIP()),
			slog.String("user_agent", c.Request.UserAgent()),
			slog.String("request_id", requestID),
		}

		if loggerConfig.EnableRequestBody && requestBody != "" {
			reqFields = append(reqFields, slog.String("request_body", requestBody))
		}

		slogger.Info("[Req]", reqFields...)

		// アプリケーション側の処理を実行
		c.Next()

		// 処理直後の時間を取得したいためインスタンス化
		latency := loggerConfig.TimeNow().Sub(start)

		// ステータスコードに応じたログレベルの設定で出力
		statusCode := c.Writer.Status()
		logLevel := getLogLevel(statusCode)

		resFields := []any{
			slog.String("method", c.Request.Method),
			slog.String("path", path),
			slog.String("query", query),
			slog.Int("status", statusCode),
			slog.String("latency", fmt.Sprintf("%.2fms", latency.Seconds()*1000)),
			slog.String("ip", c.ClientIP()),
			slog.Int("response_size", c.Writer.Size()),
			slog.String("request_id", requestID),
		}

    // エラーが発生していれば、レスポンスフィールドにエラーメッセージを表示
		var errorMsgs []string
		if len(c.Errors) > 0 {
			for _, e := range c.Errors {
				errorMsgs = append(errorMsgs, e.Error())
			}
			resFields = append(resFields, slog.Any("errors", errorMsgs))
		}

		// レスポンスのステータスコードに応じてレベルを動的に変更するため。
		slogger.Log(c.Request.Context(), logLevel, "[Res]", resFields...)
	}
}
```

:::


### 共通のインターフェース

::: details LoggerMiddlewareで使用する構造体
```go
type LoggerConfig struct {
	Level             string
	Format            string    // "json" or "text"
	TimeNow           TimeFunc  // 時刻取得関数（テスト時にモック可能）
	Writer            io.Writer // ログ出力先（アクセスログのため標準出力としてos.Stdoutを設定）
	SkipPaths         []string  // ログをスキップするパス
	EnableRequestBody bool      // リクエストボディをログ出力するか
	UUIDGen           UUIDGenerator
	MaxBodyLogSize    int64
}

```
:::

### インターフェースをファクトリー関数で定義できるよう実装

::: details ファクトリー関数とその他必要な型、ヘルパー関数
```go
// TimeFunc は時刻を取得する関数の型（例: time.Now）
type TimeFunc func() time.Time

// Option はLoggerConfigを設定するための関数型
// この型の関数は、LoggerConfigを受け取って設定を変更する
type Option func(*LoggerConfig)

// 時刻取得関数を設定するOptionを返す
// 使い方: NewLoggerConfig("info", "json", WithTimeFunc(time.Now))
func WithTimeFunc(f TimeFunc) Option {
	return func(l *LoggerConfig) {
		l.TimeNow = f
	}
}

// ログ出力先を設定するOptionを返す
// 使い方: NewLoggerConfig("info", "json", WithWriter(os.Stdout))
func WithWriter(w io.Writer) Option {
	return func(l *LoggerConfig) {
		l.Writer = w
	}
}

// WithSkipPaths は特定のパスをログから除外するOptionを返す
// ヘルスチェックエンドポイントなど、ログ不要なパスを指定
func WithSkipPaths(paths []string) Option {
	return func(l *LoggerConfig) {
		l.SkipPaths = paths
	}
}

// WithEnableRequestBody はリクエストボディのログ出力を有効化
// 注意: 機密情報が含まれる可能性があるため慎重に使用
func WithEnableRequestBody(enable bool) Option {
	return func(l *LoggerConfig) {
		l.EnableRequestBody = enable
	}
}

func WithUUIDGenerator(gen UUIDGenerator) Option {
	return func(l *LoggerConfig) {
		l.UUIDGen = gen
	}
}

func WithMaxBodyLogSize(size int64) Option {
	return func(l *LoggerConfig) {
		l.MaxBodyLogSize = size
	}
}

func NewLoggerConfig(level, format string, opts ...Option) *LoggerConfig {
	// デフォルト値でconfigを初期化
	config := &LoggerConfig{
		Level:             level,
		Format:            format,
		TimeNow:           time.Now,
		Writer:            os.Stdout,
		EnableRequestBody: false,
		UUIDGen:           &RealUUIDGenerator{},
		SkipPaths:         []string{},
		MaxBodyLogSize:    maxBodyLogSize,
	}

	// 渡されたオプション関数を順番に実行
	// opts = [
	//   func(l *LoggerConfig) { l.TimeNow = time.Now },
	//   func(l *LoggerConfig) { l.Writer = os.Stdout },
	// ]
	for _, opt := range opts {
		opt(config)
	}

	return config
}
```
:::

### ログのレベルと出力先を定義
::: details レベル & 出力先

```go
func parseLevel(level string) slog.Level {
	switch strings.ToLower(level) {
	case "debug":
		return slog.LevelDebug
	case "info":
		return slog.LevelInfo
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

func NewLogger(loggerConfig *LoggerConfig) *slog.Logger {
	level := parseLevel(loggerConfig.Level)
	opts := &slog.HandlerOptions{Level: level}

	writer := loggerConfig.Writer

	var handler slog.Handler
	switch strings.ToLower(loggerConfig.Format) {
	case "json":
		handler = slog.NewJSONHandler(writer, opts)
	case "text":
		handler = slog.NewTextHandler(writer, opts)
	default:
		handler = slog.NewTextHandler(writer, opts)
	}

	return slog.New(handler)
}

```

:::

### レスポンス時のHTTPステータスコードに応じてログのレベルを動的に設定する
::: details ステータスコードによってログレベルを分岐
```go
// HTTPステータスコードに応じたログレベルを返す
func getLogLevel(statusCode int) slog.Level {
	switch {
	case statusCode >= 500:
		return slog.LevelError
	case statusCode >= 400:
		// 404は頻発するためErrorで通知させたくない。
		return slog.LevelWarn
	case statusCode >= 300:
		return slog.LevelInfo
	default:
		return slog.LevelInfo
	}
}

```

:::

### 指定したパスはログを表示しないようSkip
::: details スキップするパスの判定

```go
func shouldSkip(path string, skipPaths []string) bool {
	for _, skipPath := range skipPaths {
		if path == skipPath {
			return true
		}
	}
	return false
}

```
:::

### 特定のContent-Typeのボディのみ表示させる
::: details 特定のContent-Typeがリクエストボディに含まれているか判定
```go
func shouldLogBody(contentType string) bool {
	allowedTypes := []string{
		"application/json",
		"application/x-www-form-urlencoded",
		"text/plain",
	}

	for _, allowedType := range allowedTypes {
		if strings.Contains(strings.ToLower(contentType), allowedType) {
			return true
		}
	}
	return false
}
```

:::

### 認証情報などログに表示させたくない値をマスキング
- 以下のように表示の際に`***MASKED***`で表示される。
  - (例)リクエストボディのKeyが`password`の場合
```shell
time=2025-10-21T16:13:25.082+09:00 level=INFO msg=[Req] method=POST path=/api/v1/users query="" ip=::1 user_agent=curl/8.7.1 request_id=9c9230d5-2c27-4b5b-b4e0-bb3bc9cca48f request_body="{\"password\":\"***MASKED***\",\"username\":\"john\"}"
```
::: details データ構造ごとに再起的なマスキングの処理

```go
var sensitiveFields = []string{
	"password",
	"token",
	"secret",
	"api_key",
	"apikey",
	"authorization",
}

// maskSensitiveData はJSONボディ内の機密情報をマスキング
func maskSensitiveData(body string) string {
	var data map[string]interface{}
	if err := json.Unmarshal([]byte(body), &data); err != nil {
		// JSONパース失敗時はそのまま返す
		return body
	}

	// 再帰的にマスキング
	masked := maskRecursive(data)

	// JSON文字列に戻す
	result, err := json.Marshal(masked)
	if err != nil {
		return body
	}
	return string(result)
}

// maskRecursive は再帰的に機密フィールドをマスキング
func maskRecursive(data interface{}) interface{} {
	switch v := data.(type) {
	case map[string]interface{}:
		// オブジェクト（マップ）の場合
		for key, value := range v {
			// キーが機密フィールドかチェック
			if isSensitiveField(key) {
				v[key] = "***MASKED***"
			} else {
				// 機密フィールドでなければ再帰的に処理
				v[key] = maskRecursive(value)
			}
		}
		return v

	case []interface{}:
		// 配列の場合
		for i, item := range v {
			v[i] = maskRecursive(item)
		}
		return v

	default:
		// string, number, bool等のプリミティブな型はそのまま
		return v
	}
}

// isSensitiveField はフィールド名が機密情報かチェック
func isSensitiveField(fieldName string) bool {
	lowerField := strings.ToLower(fieldName)
	for _, sensitive := range sensitiveFields {
		if lowerField == strings.ToLower(sensitive) {
			return true
		}
	}
	return false
}
```

:::

### リクエストIDでUUIDを生成するための依存性注入
- テストしやすくするためのinterfaceとメソッド
::: details UUIDGenerator
```go
type UUIDGenerator interface {
	Generate() string
}

type RealUUIDGenerator struct{}

func (g *RealUUIDGenerator) Generate() string {
	return uuid.New().String()
}
```
:::

## 4-3.main.go
- 今回の記事の趣旨はロギングのMiddleware実装のため、handler側は簡易的にmainに統合している。
```go
package main

import (
	"github.com/gin-gonic/gin"
	// このパスは環境に応じて置き換えてください。
	"github.com/takehiro1111/gin-api/tasks/internal/middleware"
	"net/http"
	"os"
	"time"
)

func main() {
	gin.SetMode(gin.ReleaseMode)
	router := gin.Default()

	loggerConfig := middleware.NewLoggerConfig(
		"info",
		"text",
		middleware.WithTimeFunc(time.Now),
		middleware.WithWriter(os.Stdout),
		middleware.WithEnableRequestBody(true),
		// 指定したパスのログはmiddlewareを適用しない。
		middleware.WithSkipPaths([]string{"/test2"}),
		middleware.WithMaxBodyLogSize(100),
	)
	router.Use(middleware.LoggerMiddleware(loggerConfig))

	router.GET("/test", func(c *gin.Context) {

		c.JSON(http.StatusOK, gin.H{
			"test": "OK",
		})

	})

	router.GET("/test2", func(c *gin.Context) {

		c.JSON(http.StatusOK, gin.H{
			"test2": "OK",
		})

	})

	router.Run(":8080")
}

```

# 5.参考
https://github.com/golang-standards/project-layout
https://gin-gonic.com/ja/docs/examples/custom-log-format/
https://gin-gonic.com/ja/docs/examples/custom-middleware/
https://gin-gonic.com/ja/docs/examples/using-middleware/
https://synamon.hatenablog.com/entry/2022/09/28/180048
https://zenn.dev/glassonion1/articles/8ac939208bd455
https://pkg.go.dev/io#NopCloser
https://pkg.go.dev/github.com/gin-gonic/gin@v1.11.0#section-readme
https://pkg.go.dev/github.com/gin-gonic/gin@v1.11.0#Context.ClientIP
