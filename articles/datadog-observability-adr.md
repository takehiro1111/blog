---
title: "オブザーバビリティの課題から Datadog を選定し、設計・実装・運用するまで"
emoji: "🐶"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Datadog", "SRE", "Observability", "ECS", "Terraform"]
published: false
publication_name: triplethree
---

![](/images/datadog/logo.png =400x)


## この記事で書くこと
弊社ではオブザーバビリティツールとしてDatadogを運用しています。
今年の6月頃から導入しているのですが、なぜDatadogを使用しているのかを振替し判断記録として残したいと思います。

- 導入前時点での状況と課題
- オブザーバビリティツールとしてのDatadogを選定するまでに考えたこと、判断基準
- 導入時に設計で決めたこと
- 実装でやったこと、ハマったこと
- 運用して分かったこと
- 残っている課題

## 前提
弊社のメインプロダクトで採用している技術スタックと運用体制です。

- FE: TypeScript（React）
- BE: Go（chi）
- インフラ: AWS(ECS Fargate)
- IaC: AWS CDK
- 運用体制: 開発者がインフラも含めて技術横断的に対応し、CTO が強い権限を持っている

## 導入前に抱えていた課題

一番大きかったのは、監視の大方針が決まっていなかったことです。
AWS のサービスに寄せるのか、SaaS を使うのかが決まっていないため、ログ・メトリクス・監視の整備がどれも進められない状態でした。

ログは各アプリが CloudWatch Logs に出しているだけでした。
後で棚卸しすると、バックエンド 6 プロダクトのうち 4 つはアクセスログ自体が出ておらず、残りの 2 つも旧形式の属性で全て Info レベルだったり、4xx しか出ていなかったりしました。

また、ゴールデンシグナル（レイテンシ・トラフィック・エラー・サチュレーション）で測れない異常を拾えないことも課題でした。
応募者とのチャット機能で 400 系のエラーが出ていたものの、アラートでは検知できず、修正までに気付くのが遅れた事象がありました。

## 1. 選定

### 考えたこと

2026年5月から可観測性の調査を始めました。
最初に決める必要があったのは「AWS に寄せるか、SaaS を使うか」です。

AWS のサービスで組む案として、次の 3 つを検討しました。

| 案 | 構成 | 気になった点 |
|---|---|---|
| S3 + Athena + Redash | ログを S3 に置いてクエリする | 容量の上限、ライフサイクルポリシー、ストレージクラスの設計を自分たちで持つ必要がある |
| Firehose + OpenSearch | ログを OpenSearch に集約して検索する | OpenSearch の固定費が高い |
| CloudWatch | CloudWatch Logs と CloudWatch Dashboard | ログ・メトリクス・トレースを横断して辿るのが難しい |

SaaS は Datadog / New Relic / Mackerel / Sentry / Dynatrace の機能と料金を調べました。

New Relic は課金がホスト数ではなく取り込みデータ量とユーザー数で決まり、月 100GB の無料枠があります。
トラフィックが小さい今の規模なら無料枠に収まる可能性が高く、費用面では最も有力でした。

Sentry はアプリ内部のエラー監視が本職で、CPU やメモリなどのインフラメトリクスは守備範囲外です。
トレース・メトリクス・ログを紐付けて辿ることもできません。

Datadog は機能の幅と、エラー → トレース → ログ → インフラを 1 画面で辿れる点が強みです。
一方で、課金項目が 10 種類以上あり、監視対象や機能を増やすほど費用が積み上がる点が懸念でした。

Datadog とは見積もりの段階でやり取りをしました。
Lambda は 1 時間に 1 回以上実行された関数がアクティブ関数として課金されること、ログは取り込みとインデックス化を切り離す Logging without Limits の考え方で、保持期間 30 日を前提にすることを確認しました。
Lambda で動かしているのは一部の機能だけなので、Lambda は Datadog の監視に含めず CloudWatch でエラーログを見る形で良いと判断しました。

### 判断基準

判断基準にしたのは次の 4 つです。

- 監視基盤の構築・運用工数を抑えられるか
  - インフラ・SRE 担当が少人数なので、監視基盤そのものを自前で組んで運用する余力が無い
- 障害対応を速くできるか
  - HR プロダクトとして安定稼働が重要で、障害時に原因まで辿り着く時間を短くしたい
- ログ・トレース・メトリクスを紐付けて辿れるか
  - 冒頭の「ゴールデンシグナルで測れない異常」に気付くには、1 つのエラーから関連する情報を横断して見る必要がある
- 費用が見合うか

### 選定結果

6 月 1 日の時点で、候補は次の 2 案に絞られました。

```md
A. Sentry + AWS の機能（OpenSearch など費用の高いサービスは使わない）
  → 月 3〜5 万円（仮）

B. Datadog で統合
  → 月 9〜13 万円程度
```

可観測性をしっかり実現するなら B 案、費用とプロダクトのフェーズを考えた妥協案が A 案という整理です。

<!-- TODO: A 案と B 案から Datadog に決めた理由（決め手）を記入する。Notion の MTG サマリには記載が見つからなかった -->
最終的に Datadog を選びました。

## 2. 設計

6 月 8 日から導入作業に入り、次のことを決めました。

```md
1. 計装と設定の責務を分ける
  - 計装（Agent・ログ転送・APM・RUM）は各プロダクトのアプリと CDK で行う
  - 収集したデータに対する monitor / dashboard / SLO などの設定は、
    Datadog 専用の Terraform リポジトリで管理する

2. ECS には Datadog Agent と Fluent Bit をサイドカーで入れる
  - Agent が止まってもアプリは止めない
  - Fluent Bit が止まったらタスクごと止め、ログを取りこぼさない

3. APM は Orchestrion による自動計装にする
  - ベンダーロックインは当面気にせず、Datadog に寄せる

4. service / env タグを Agent・ログ・トレースで揃える

5. アラートの優先度を P1〜P5 で定義する

6. ログは INFO も取り込み、不要なものは index から外す
```

### 計装と設定の責務を分ける

計装はアプリの実装や ECS のタスク定義に依存するため、各プロダクトのリポジトリに置くのが自然です。
一方で、monitor や dashboard はプロダクトを横断して同じ形で揃えたいものです。
各プロダクトのリポジトリに散らばると、通知文面や閾値の考え方を揃えるたびに全リポジトリを直すことになります。
そのため、Datadog 上の設定だけは 1 つのリポジトリにまとめました。

### ECS には Agent と Fluent Bit をサイドカーで入れる

ログだけでなくメトリクスと APM も取り込みたいため、Datadog が提供する CDK の Construct（`datadog-cdk-constructs-v2` の `DatadogECSFargate`）を使いました。
タスク定義を直接書き換えるより記述量が少なく、各プロダクトへ横展開しやすいことも理由です。

Agent とログルーターでは、止まった時の扱いを逆にしています。

- Agent（`isDatadogEssential: false`）
  - Agent が止まってもアプリのコンテナは動き続ける。監視のためにサービスを止めない
- Fluent Bit（`isLogRouterEssential: true`）
  - Fluent Bit が止まったらタスクごと止めて再起動させる。ログの取りこぼしを避ける

### APM は自動計装にする

Go アプリの APM は、Orchestrion によるコンパイル時の自動計装にしました。
`orchestrion go build` がビルド時に `net/http`・`go-chi`・`database/sql` などへスパンを作るコードを挿入するため、アプリのコードを変更せずにトレースを送れます。

手動計装に切り替える時にベンダーロックインをどこまで避けるかも議論しましたが、現段階では気にせず Datadog に寄せる方針にしました。
手動計装は、運用の中で自動計装では足りない課題が出てから対応します。

### service / env タグを揃える

`service` と `env` の値が Agent・ログ・トレースでずれると、同じサービスとして紐付かず、横断検索もできなくなります。
そのため CDK の中で service 名を 1 つの変数にし、Agent とログドライバの両方に同じ値を渡すことにしました。

### アラートの優先度を P1〜P5 で定義する

| Priority | 基準 |
|---|---|
| P1 | ユーザーがサービスを利用できない |
| P2 | 一部機能に影響がある、または放置すると P1 になる |
| P3 | 品質劣化はあるが機能は使える |
| P4 | 将来的にリスクになる兆候 |
| P5 | 情報収集・改善提案 |

Synthetics / APM / Log / RUM などの種類ごとに、どの事象をどの優先度にするかを対応付けました。
P1 は専用の Slack チャンネルにも通知し、それ以外と見分けられるようにしています。

## 3. 実装

### ECS のサイドカー設定

`DatadogECSFargate` の設定は次のようになりました。

```ts
const ddService = projectHyphen;

const datadog = new DatadogECSFargate({
  apiKeySecret: props.datadogApiKeySecret,
  imageVersion: "7.79.2",
  site: "ap1.datadoghq.com",
  isDatadogEssential: false,
  env,
  service: ddService,
  globalTags: `env:${env},region:ap-northeast-1`,
  apm: {
    isEnabled: true,
    isSocketEnabled: true,
    traceInferredProxyServices: true,
  },
  dogstatsd: {
    isEnabled: true,
    isOriginDetectionEnabled: true,
    isSocketEnabled: true,
  },
  logCollection: {
    isEnabled: true,
    loggingType: LoggingType.FLUENTBIT,
    fluentbitConfig: {
      isLogRouterEssential: true,
      firelensOptions: {
        isParseJson: true,
      },
      logDriverConfig: {
        hostEndpoint: "http-intake.logs.ap1.datadoghq.com",
        serviceName: ddService,
        sourceName: "go",
      },
    },
  },
});
```

この設定に落ち着くまでに、いくつかハマりました。

1 つ目は、ログだけが Datadog に届かなかったことです。
Construct のログ送信先の既定値は US1 の intake で、`site` を ap1 にしても連動しません。
そのためログだけ US1 に送られ、AP1 の API キーで弾かれていました。
`hostEndpoint` で AP1 の intake を明示して解消しました。

2 つ目は、ログが JSON として解釈されなかったことです。
アプリは slog の JSON 構造化ログを標準出力に出していますが、`isParseJson` が既定の false だと Fluent Bit は 1 行をただの文字列として送ります。
Datadog 上では JSON が message の文字列のまま入り、`@http.method` や `@http.status_code` のような属性で検索できませんでした。

3 つ目は、`serviceName` / `sourceName` を指定しないと、アプリのコンテナのログが service 空・`source:undefined` で取り込まれることです。
これではトレースと紐付きません。

4 つ目は、CDK の synth が落ちたことです。
`isLogRouterEssential: true` にすると、essential なログルーターのコンテナがアプリより先にタスク定義へ追加され、タスク定義の既定のコンテナになります。
ALB のターゲットを暗黙で指定していると、ポートを持たないログルーターに紐付こうとしてエラーになります。
アプリのコンテナとポートを明示的にターゲットに指定して解消しました。

```ts
targets: [
  fargateService.loadBalancerTarget({
    containerName: "server",
    containerPort: 80,
  }),
],
```

サイドカーが増える分、CPU / メモリが逼迫して起動できない、OOM になる、性能が落ちる可能性もあります。
その場合はタスク定義の `cpu` / `memory` を増やす前提で各プロダクトへ展開しました。

### Orchestrion による自動計装

アプリ側の変更は、`orchestrion.tool.go` の追加と Dockerfile のビルドコマンドの置き換えだけです。

```go
//go:build tools

//go:generate go run github.com/DataDog/orchestrion pin -generate

package tools

import (
	_ "github.com/DataDog/orchestrion"
	_ "github.com/DataDog/dd-trace-go/orchestrion/all/v2"
)
```

```diff docker
 FROM base AS builder
+RUN go install github.com/DataDog/orchestrion
+COPY orchestrion.tool.go .
 COPY cmd/ ./cmd/
-RUN GOOS=linux GOARCH=arm64 CGO_ENABLED=1 go build -v -o /work/target ./cmd/...
+RUN GOOS=linux GOARCH=arm64 CGO_ENABLED=1 orchestrion go build -v -o /work/target ./cmd/...
```

`go install` にバージョンを付けないことで、`go.mod` に固定したバージョンの Orchestrion が使われます。
Orchestrion の対応バージョンに合わせて、Go は 1.25 に引き上げました。

### Datadog の設定を Terraform で管理する

7 月の頭に datadog-terraform リポジトリを作りました。
Datadog 上には、画面や API から作られた monitor・dashboard が既にあったため、まず既存のリソースを import してコードに移しました。

state はプロダクト単位で分け、プロダクト横断の dashboard やログの設定は `shared/` 配下に置いています。

```
aws/            tfstate の S3 バケット、CI 用の IAM ロール、API キーの Secrets Manager
<product>/prod/ プロダクトごとの monitor と RUM application
shared/         dashboard、ログの index / pipeline、コスト監視など org 共通の設定
modules/        通知文面の共通テンプレートなど
```

PR で `terraform plan` を実行して結果をコメントに出し、マージで `terraform apply` する流れは Digger で組みました。
provider や Terraform のバージョンは Renovate で自動更新しています。

monitor の通知文面は、プロダクトをまたいでほぼ同じになります。
各プロダクトの `monitor.tf` に直書きすると、文面を改善するたびに全プロダクトへ横展開が必要になるため、`alert_message` モジュールに共通のテンプレートを置きました。
プロダクト側は service 名・env・通知先だけを渡します。

```hcl
module "alert_message" {
  source = "../../modules/alert_message"

  service_backend      = "triple-report-backend"
  env                  = "production"
  product_display_name = "TRIPLE REPORT"
  # ...
}

resource "datadog_monitor" "apm_error_rate" {
  name     = "[TRIPLE REPORT BE] APM エラー率が高い"
  type     = "query alert"
  priority = 1
  message  = module.alert_message.body.apm_error_rate
  # ...
}
```

テンプレートは「発生内容 → 重大度 → 影響 → 対応手順」の順に揃え、通知を見た時点で何をすれば良いか分かるようにしています。

### ログの標準化

Datadog にログが届くようになった後、7 月末から 6 プロダクトのアクセスログを整備しました。

- 属性を Datadog の標準属性（`http.method` / `http.status_code` / `duration` など）に揃える
- ステータスコードに応じてログレベルを分ける
- `http.route` に chi のルートパターンを入れ、エンドポイント単位で集計できるようにする
- ログにトレース ID を付け、ログとトレースを双方向に辿れるようにする

アクセスログの 5xx を検知する専用の monitor も 8 月に追加しました。
monitor は新旧どちらの属性でも拾えるように書き、アプリの修正がデプロイされる前から有効になるようにしています。

### ログの PII の除去

整備の途中で、ログにメールアドレスや JWT などの個人情報・資格情報が平文で出ている箇所が見つかりました。
本筋はアプリ側で出さないことなので、各プロダクトのコードを修正しました。
それに加えて、取りこぼしを受け止める保険として、Datadog Sensitive Data Scanner（取り込み時にマスク）で JWT とメールアドレスを伏せ字にしています。

## 4. 運用

### アラートの棚卸し

導入して 2 か月ほど経った 9 月に、直近 7 日間のアラート発報をプロダクト横断で棚卸ししました。

分かったのは、全アラートの 80% が RUM の 5 つの monitor から出ていて、しかも通知先が設定されていなかったことです。
誰にも届かないアラートが大半を占めていました。
他にも、正常な処理を ERROR で記録しているためにエラーログの monitor が何度も発報しているケースや、通知先が個人のメールだけになっている monitor が見つかりました。

<!-- TODO: 通知先の修正（RUM 5 モニター・Apdex モニター）がその後マージされたか確認する。datadog-terraform の main の履歴には見当たらなかった -->
棚卸しの結果から、RUM の monitor に通知先を設定する修正などを進めました。

閾値は、棚卸しの前の 9 月上旬に、プロダクトごとの実測値に合わせて較正しています。

### コストの監視

Datadog の懸念だった費用は、利用量のメトリクス（`datadog.estimated_usage.*` など）で監視しています。
課金のモデルが SKU ごとに違うため、監視の仕方も分けました。

| 課金モデル | 例 | 監視の仕方 |
|---|---|---|
| コミット枠なし（使った分がそのままオンデマンド課金） | Infra Hosts / Ingested Logs | 実測の 2〜3 倍に置いた急増ガード |
| コミット枠あり（超過分がオンデマンド課金） | Fargate / RUM / Indexed Logs | 枠の 80%（warning）/ 90%（critical）で通知 |

月の累計は、請求のカレンダー月と揃うよう月初起点の `current_1mo` で評価しています。
コストの超過は障害ではないため、P1 の通知先には流さず priority は 3 にしています。

## 残っている課題

- SLO はまだ設定できていない
- test 環境のデータは Datadog に送っておらず、本番だけを見ている
- アプリログは、エラーを `error.message` / `error.kind` / `error.stack` に入れる形への移行と、トレース ID を付けるための ctx 付きロガーへの移行が残っている
- ユーザー ID（`usr.id`）を Logs / APM / RUM で同じ値・同じ型に揃えられておらず、ユーザー単位での横断検索ができない
- AWS インテグレーションは CloudWatch API の費用を抑えるため一部に絞っており、ALB や RDS の CloudWatch メトリクスは Datadog で見ていない

## 最後に

<!-- TODO: 振り返り・今後の展望 -->

## We're Hiring!

TRIPLE THREE では、少人数 × AI 前提で開発も業務も回す仲間を募集しています！
カジュアル面談もやっているので、話だけでも聞いてみたい！という方も大歓迎です。
興味のある方は是非のぞいてみてください！

@[card](https://www.333-inc-intra.com/?v=18ad08d1a1f581ae9317000cc9071a00)
