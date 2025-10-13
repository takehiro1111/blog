---
title: "[Go]RateLimitingを適用するミドルウェアの実装"
emoji: "📘"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Go", "RateLimit"]
published: false
---
![](/images/go/go_logo.png =450x)

## 本記事の内容

- Go で IP ベースでレート制限をかける際の具体的な実装(ミドルウェアとして記載)
- 以下は本記事では触れない。
  - IP ベース以外の制限での実装
  - RateLimit についての説明
  - インフラ側だと WAF で IP ベースでのレート制限を行うこともありますが、今回の記事では考慮に入れてません。

## 機能要件

- 同一 IP からのリクエスト回数を制限
- 1分間に10回までと制限を行い、利用可能なトークンがない場合は`429 Too Many Requests` を返す。
	- Token Bucket方式でバースト許容(一時的な急増OK)を採用しています。
- ミドルウェアとして実装してラップすることで全てのエンドポイントに適用できる。
- メモリの中で 30 分より以前の ratelimiter に関するログは保持しないことでメモリリーク対策を行う。
- 依存性を注入しテストコードでMockを作れるよう実装すること。

## 実装

- middleware として実装しています。

```go:ratelimit.go
package main

import (
	"log"
	"net"
	"net/http"
	"sync"
	"time"
	"golang.org/x/time/rate"
)

const (
	ErrMsgBadRequest     = "Bad Request"
	ErrMsgTooManyRequest = "Too Many Requests"
)


// テスト時に現在時刻に依存しないモックを作成するためにinterfaceを定義
type timeProvider interface {
	Now() time.Time
}

// 本番環境用の時刻プロバイダー実装
type RateLimitRealTimeProvider struct{}

func (*RateLimitRealTimeProvider) Now() time.Time {
	return time.Now()
}

// レート制限とクリーンアップの設定
type RateLimitConfig struct {
	TimeProvider      timeProvider
	CleanupInterval   time.Duration
	InactiveThreshold time.Duration
	RateLimit         time.Duration
	Burst             int
}

// クリーンアップ判定のため最終アクセス時刻を記録
type limiterInfo struct {
	limiter    *rate.Limiter
	lastAccess time.Time
}

// 複数のリクエスト間での状態を共有するためにグローバル変数を使用
var (
	mu         sync.Mutex
	limiters   = make(map[string]*limiterInfo)
	timeConfig *RateLimitConfig
)

// テスト用のDI
func InitRateLimiter(cfg *RateLimitConfig) {
	timeConfig = cfg
}

// メモリリークを防ぐため定期的にクリーンアップを実行
func StartCleanup() {
	if timeConfig == nil {
		timeConfig = &RateLimitConfig{
			TimeProvider:      &RateLimitRealTimeProvider{},
			CleanupInterval:   10 * time.Minute,
			InactiveThreshold: -30 * time.Minute,
			RateLimit:         time.Minute / 10,
			Burst:             10,
		}
	}

	ticker := time.NewTicker(timeConfig.CleanupInterval)
	go func() {
		for range ticker.C {
			cleanupLimiters()
		}
	}()
}

func cleanupLimiters() {
	mu.Lock()
	defer mu.Unlock()

	// メモリの中で30分以上アクセスのないIPのratelimiter情報は削除される。
	// 30分という値は便宜上キリの良い閾値として設定しています。
	threshold := timeConfig.TimeProvider.Now().Add(timeConfig.InactiveThreshold) // 30min
	count := 0

	for ip, info := range limiters {
		// 30分より前と境界も削除する。
		if info.lastAccess.Before(threshold) || info.lastAccess.Equal(threshold) {
			delete(limiters, ip)
			count++
		}
	}

	if count > 0 {
		log.Printf("Cleaned up %d inactive rate limiters\n", count)
	}
}

func getLimiter(ip string) *rate.Limiter {
	mu.Lock()
	defer mu.Unlock()

	// 同一IPで既存のratelimitが設定されている場合は取得のみ
	info, exists := limiters[ip]
	if exists {
		limiters[ip].lastAccess = timeConfig.TimeProvider.Now()
		return info.limiter
	}

	limit := rate.Every(timeConfig.RateLimit)
	burst := timeConfig.Burst

	// 6秒毎に1トークン蓄積 / 10トークン分のburst可能
	limiter := rate.NewLimiter(limit, burst)
	limiters[ip] = &limiterInfo{
		limiter:    limiter,
		lastAccess: timeConfig.TimeProvider.Now(),
	}

	return limiter
}

func RateLimit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// プロキシやロードバランサーを経由する場合を想定して
		var ip string
		var err error
		ip = r.Header.Get("X-Forwarded-For")
		if ip == "" {
			ip, _, err = net.SplitHostPort(r.RemoteAddr)
			if err != nil {
				http.Error(w, ErrMsgBadRequest, http.StatusBadRequest)
				return
			}
		}

		limiter := getLimiter(ip)

		if !limiter.Allow() {
			// クライアントへ警告
			w.Header().Set("Retry-After", "60")
			log.Printf("Rate limit exceeded for IP: %s\n", ip)
			http.Error(w, ErrMsgTooManyRequest, http.StatusTooManyRequests)
			return
		}

		next.ServeHTTP(w, r)
	})
}
```

## 単体テスト

```go
package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"golang.org/x/time/rate"
)

var fixedTimeRateLimit = time.Date(2024, 12, 2, 13, 0, 0, 0, time.UTC)

type MockRateLimitRealTimeProvider struct {
	currentTime time.Time
}

// Mockで時刻を固定することで静的な値にしてテストを安定化させている。
func (m *MockRateLimitRealTimeProvider) Now() time.Time {
	return m.currentTime
}

func resetRateLimiter() {
	mu.Lock()
	defer mu.Unlock()
	limiters = make(map[string]*limiterInfo)
	timeConfig = nil
}

func TestCleanupLimiters(t *testing.T) {
	tests := []struct {
		name            string
		setupIPs        map[string]time.Time
		expectedIpCount int
		expectedIPs     []string
	}{
		{
			name: "正常系: 30分以上古いエントリが削除される",
			setupIPs: map[string]time.Time{
				"192.168.1.1": fixedTimeRateLimit.Add(-40 * time.Minute),
				"192.168.1.2": fixedTimeRateLimit.Add(-29 * time.Minute),
			},
			expectedIpCount: 1,
			expectedIPs:     []string{"192.168.1.2"},
		},
		{
			name: "正常系: 全てのエントリが30分未満なら削除されない",
			setupIPs: map[string]time.Time{
				"192.168.1.1": fixedTimeRateLimit.Add(-10 * time.Minute),
				"192.168.1.2": fixedTimeRateLimit.Add(-20 * time.Minute),
			},
			expectedIpCount: 2,
			expectedIPs:     []string{"192.168.1.1", "192.168.1.2"},
		},
		{
			name:            "正常系: limitersが空でもエラーにならない",
			setupIPs:        map[string]time.Time{},
			expectedIpCount: 0,
			expectedIPs:     []string{},
		},
		{
			name: "境界値: ちょうど30分のRateLimiterは削除される",
			setupIPs: map[string]time.Time{
				"192.168.1.1": fixedTimeRateLimit.Add(-30 * time.Minute),
			},
			expectedIpCount: 0,
			expectedIPs:     []string{},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			resetRateLimiter()

			mockTime := &MockRateLimitRealTimeProvider{
				currentTime: fixedTimeRateLimit,
			}
			mockTimeConfig := &RateLimitConfig{
				TimeProvider:      mockTime,
				CleanupInterval:   10 * time.Minute,
				InactiveThreshold: -30 * time.Minute,
				RateLimit:         time.Minute / 10,
				Burst:             10,
			}
			InitRateLimiter(mockTimeConfig)

			mu.Lock()
			for ip, lastAccess := range tc.setupIPs {
				limiters[ip] = &limiterInfo{
					limiter:    rate.NewLimiter(rate.Every(mockTimeConfig.RateLimit), mockTimeConfig.Burst),
					lastAccess: lastAccess,
				}
			}
			mu.Unlock()

			cleanupLimiters()

			// 残っているIPの数を確認
			mu.Lock()
			assert.Equal(t, tc.expectedIpCount, len(limiters))

			// 残っているIPが正しいか確認
			for _, ip := range tc.expectedIPs {
				_, exists := limiters[ip]
				assert.True(t, exists, "IP %s should exist", ip)
			}
			mu.Unlock()
		})
	}
}

func TestRateLimit(t *testing.T) {
	tests := []struct {
		name                string
		method              string
		path                string
		requestCount        int
		remoteAddr          string
		xForwardedFor       string
		expectedOK          int
		expectedBlocked     int
		expectedStatus      int
		expectedHeaderValue string
	}{
		{
			name:                "正常系: 制限内(10回)のリクエストは全て成功",
			method:              "GET",
			path:                "/hello",
			requestCount:        10,
			remoteAddr:          "192.168.1.1:12345",
			expectedOK:          10,
			expectedBlocked:     0,
			expectedStatus:      http.StatusOK,
			expectedHeaderValue: "",
		},
		{
			name:                "正常系: 60秒に10を超えるリクエストはRateLimitが発動する",
			method:              "GET",
			path:                "/hello",
			requestCount:        15,
			remoteAddr:          "192.168.1.1:12345",
			expectedOK:          10,
			expectedBlocked:     5,
			expectedStatus:      http.StatusTooManyRequests,
			expectedHeaderValue: "60",
		},
		{
			name:                "正常系: X-Forwarded-Forヘッダーが優先される",
			method:              "GET",
			path:                "/hello",
			requestCount:        11,
			remoteAddr:          "192.168.1.1:12345",
			xForwardedFor:       "10.0.0.1",
			expectedOK:          10,
			expectedBlocked:     1,
			expectedStatus:      http.StatusTooManyRequests,
			expectedHeaderValue: "60",
		},
		{
			name:                "異常系: RemoteAddrが不正な形式の場合は400エラー",
			method:              "GET",
			path:                "/hello",
			requestCount:        1,
			remoteAddr:          "invalid-format",
			expectedOK:          0,
			expectedBlocked:     1,
			expectedStatus:      http.StatusBadRequest,
			expectedHeaderValue: "",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			resetRateLimiter()

			testHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(http.StatusOK)
				w.Write([]byte("OK"))
			})

			mockTimeConfig := &RateLimitConfig{
				TimeProvider: &MockRateLimitRealTimeProvider{
					currentTime: fixedTimeRateLimit,
				},
				CleanupInterval:   10 * time.Minute,
				InactiveThreshold: -30 * time.Minute,
				RateLimit:         time.Minute / 10,
				Burst:             10,
			}
			InitRateLimiter(mockTimeConfig)
			wrappedHandler := RateLimit(testHandler)

			okCount := 0
			blockedCount := 0

			for i := 0; i < tc.requestCount; i++ {
				req := httptest.NewRequest(tc.method, tc.path, nil)
				req.RemoteAddr = tc.remoteAddr
				if tc.xForwardedFor != "" {
					req.Header.Set("X-Forwarded-For", tc.xForwardedFor)
				}
				w := httptest.NewRecorder()
				wrappedHandler.ServeHTTP(w, req)

				if w.Code == http.StatusOK {
					okCount++
				} else {
					blockedCount++
					assert.Equal(t, tc.expectedStatus, w.Code)
					if tc.expectedHeaderValue != "" {
						assert.Equal(t, tc.expectedHeaderValue, w.Header().Get("Retry-After"))
					}
				}
			}

			assert.Equal(t, tc.expectedOK, okCount)
			assert.Equal(t, tc.expectedBlocked, blockedCount)
		})
	}
}

```

### main 関数でラップする

```go:main.go

package main

import (
	"log"
	"net/http"
	"fmt"
)

func HelloHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "Hello, world!\n")
}

func main() {
	// RateLimitの定期クリーンアップ開始（10分ごとにバックグラウンドで実行）
	StartCleanup()

	http.HandleFunc("/hello", HelloHandler)

	// サーバー全体にRateLimitを適用している
	err := http.ListenAndServe(":8083", RateLimit(http.DefaultServeMux))
	if err != nil {
		log.Fatal(err.Error())
	}
}
```

## 実行結果

- 単体テスト

```shell
$go test -run TestCleanupLimiters -v
$go test -run TestCleanupLimiters -v
=== RUN   TestCleanupLimiters
=== RUN   TestCleanupLimiters/正常系:_30分以上古いエントリが削除される
2025/10/13 16:19:46 Cleaned up 1 inactive rate limiters
=== RUN   TestCleanupLimiters/正常系:_全てのエントリが30分未満なら削除されない
=== RUN   TestCleanupLimiters/正常系:_limitersが空でもエラーにならない
=== RUN   TestCleanupLimiters/境界値:_ちょうど30分だとIPのログは削除される
2025/10/13 16:19:46 Cleaned up 1 inactive rate limiters
--- PASS: TestCleanupLimiters (0.00s)
    --- PASS: TestCleanupLimiters/正常系:_30分以上古いエントリが削除される (0.00s)
    --- PASS: TestCleanupLimiters/正常系:_全てのエントリが30分未満なら削除されない (0.00s)
    --- PASS: TestCleanupLimiters/正常系:_limitersが空でもエラーにならない (0.00s)
    --- PASS: TestCleanupLimiters/境界値:_ちょうど30分だとIPのログは削除される (0.00s)
PASS
ok  	go-learning/tasks/api/http	0.201s

$go test -run TestRateLimit  -v
=== RUN   TestRateLimit
=== RUN   TestRateLimit/正常系:_制限内(10回)のリクエストは全て成功
=== RUN   TestRateLimit/正常系:_60秒に10を超えるリクエストはRateLimitが発動する
2025/10/13 15:20:24 Rate limit exceeded for IP: 192.168.1.1
2025/10/13 15:20:24 Rate limit exceeded for IP: 192.168.1.1
2025/10/13 15:20:24 Rate limit exceeded for IP: 192.168.1.1
2025/10/13 15:20:24 Rate limit exceeded for IP: 192.168.1.1
2025/10/13 15:20:24 Rate limit exceeded for IP: 192.168.1.1
=== RUN   TestRateLimit/正常系:_X-Forwarded-Forヘッダーが優先される
2025/10/13 15:20:24 Rate limit exceeded for IP: 10.0.0.1
=== RUN   TestRateLimit/異常系:_RemoteAddrが不正な形式の場合は400エラー
--- PASS: TestRateLimit (0.00s)
    --- PASS: TestRateLimit/正常系:_制限内(10回)のリクエストは全て成功 (0.00s)
    --- PASS: TestRateLimit/正常系:_60秒に10を超えるリクエストはRateLimitが発動する (0.00s)
    --- PASS: TestRateLimit/正常系:_X-Forwarded-Forヘッダーが優先される (0.00s)
    --- PASS: TestRateLimit/異常系:_RemoteAddrが不正な形式の場合は400エラー (0.00s)
PASS
ok  	go-learning/tasks/api/http	0.201s
```

### シェルスクリプトで`curl`叩いてレスポンスを確認

```zsh: test_ratelimit.sh
#!/bin/zsh

for i in {1..20}
do
  echo "${i}回目"
  curl -i http://localhost:8083/hello
done

```

:::details レスポンス

```zsh
$source test_ratelimit.sh
1回目
HTTP/1.1 200 OK
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 13
Content-Type: text/plain; charset=utf-8

Getting data
2回目
HTTP/1.1 200 OK
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 13
Content-Type: text/plain; charset=utf-8

Getting data
3回目
HTTP/1.1 200 OK
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 13
Content-Type: text/plain; charset=utf-8

Getting data
4回目
HTTP/1.1 200 OK
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 13
Content-Type: text/plain; charset=utf-8

Getting data
5回目
HTTP/1.1 200 OK
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 13
Content-Type: text/plain; charset=utf-8

Getting data
6回目
HTTP/1.1 200 OK
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 13
Content-Type: text/plain; charset=utf-8

Getting data
7回目
HTTP/1.1 200 OK
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 13
Content-Type: text/plain; charset=utf-8

Getting data
8回目
HTTP/1.1 200 OK
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 13
Content-Type: text/plain; charset=utf-8

Getting data
9回目
HTTP/1.1 200 OK
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 13
Content-Type: text/plain; charset=utf-8

Getting data
10回目
HTTP/1.1 200 OK
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 13
Content-Type: text/plain; charset=utf-8

Getting data
11回目
HTTP/1.1 429 Too Many Requests
Content-Type: text/plain; charset=utf-8
Retry-After: 60
X-Content-Type-Options: nosniff
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 18

Too Many Requests
12回目
HTTP/1.1 429 Too Many Requests
Content-Type: text/plain; charset=utf-8
Retry-After: 60
X-Content-Type-Options: nosniff
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 18

Too Many Requests
13回目
HTTP/1.1 429 Too Many Requests
Content-Type: text/plain; charset=utf-8
Retry-After: 60
X-Content-Type-Options: nosniff
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 18

Too Many Requests
14回目
HTTP/1.1 429 Too Many Requests
Content-Type: text/plain; charset=utf-8
Retry-After: 60
X-Content-Type-Options: nosniff
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 18

Too Many Requests
15回目
HTTP/1.1 429 Too Many Requests
Content-Type: text/plain; charset=utf-8
Retry-After: 60
X-Content-Type-Options: nosniff
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 18

Too Many Requests
16回目
HTTP/1.1 429 Too Many Requests
Content-Type: text/plain; charset=utf-8
Retry-After: 60
X-Content-Type-Options: nosniff
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 18

Too Many Requests
17回目
HTTP/1.1 429 Too Many Requests
Content-Type: text/plain; charset=utf-8
Retry-After: 60
X-Content-Type-Options: nosniff
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 18

Too Many Requests
18回目
HTTP/1.1 429 Too Many Requests
Content-Type: text/plain; charset=utf-8
Retry-After: 60
X-Content-Type-Options: nosniff
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 18

Too Many Requests
19回目
HTTP/1.1 429 Too Many Requests
Content-Type: text/plain; charset=utf-8
Retry-After: 60
X-Content-Type-Options: nosniff
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 18

Too Many Requests
20回目
HTTP/1.1 429 Too Many Requests
Content-Type: text/plain; charset=utf-8
Retry-After: 60
X-Content-Type-Options: nosniff
Date: Mon, 13 Oct 2025 06:23:18 GMT
Content-Length: 18

Too Many Requests
```

:::

## 参考
https://qiita.com/shikuno_dev/items/f5766300ae30b097917b
https://blastengine.jp/blog_content/rate-limit/
https://pkg.go.dev/golang.org/x/time/rate
https://pkg.go.dev/go.uber.org/ratelimit
https://zenn.dev/persimmon1129/articles/rate-limit-golang
https://speakerdeck.com/matumoto/gonoratelimitchu-li-noshi-zhuang
