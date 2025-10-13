---
title: "Prometheus + Step Functions + Lambdaで構築するサーバレスオンコール基盤"
emoji: "🦔"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["AWS", "Prometheus", "StepFunctions", "Lambda", "監視"]
published: false
publication_name: "nextbeat"
---

## 1. 前提

### オンコール体制の方針

- 弊社では全員 CTO というテーマを掲げて、各エンジニアが主体的に事業及びプロダクトに関わる文化を醸成しています。
  それに伴い、オンコール体制もエンジニア全員が参加する体制をとっています。

### 具体的な監視項目

- 監視項目は大きく分けて 2 つあります。
  - アプリケーションの死活監視
    - 設定したエンドポイントを GET で叩き、HTTP ステータスコード`200`以外を一定時間連続で検知した場合に Slack 通知、架電を実施
  - アプリケーションのリソース監視
    - 具体的には一部機能で使用している`EC2`、`OpenSearch`の`CPU`、`Memory`、`Storage`のメトリクス

## 2. アーキテクチャ

![](/images/nb/monitor_alerts.png =1000x)

### オンコール通知のフロー

1. `Prometheus`でアプリケーションの死活監視、インフラのリソース監視を実施
2. `AlertManager`でアラートを受け取り、`API Gateway`のエンドポイントを叩いて`Step Functions`を起動
3. `Step Functions`で`Lambda`を順次実行するワークフローを管理
4. `Lambda`で Slack 通知、各開発者の携帯への架電を実施

## 3. 各コンポーネントの説明

URL 監視を例に、主要なコンポーネントについてざっくり説明します。

### 3-1. Prometheus

#### 全体のアラートルール

- `PromQL`でシンプルにレスポンスが`200`で返ってこない場合にアラートを発火するルールにしています。

```yaml
- alert: URL Alert(critical)
    expr: probe_success == 0
    for: 5m
    labels:
      severity: critical # critical or warning
```

#### URL 監視

- エンドポイントを指定し、別コンポーネントに切り出している`blackbox-exporter`を利用して監視しています。

```yaml
 - job_name: 'product-A-url'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
        - https://hoge.com/fuga
        - https://hoge.com/piyo
```

### 3-2. AlertManager

- Prometheus のアラートを受け取り、API Gateway のエンドポイントを叩いて Step Functions を起動します。

```yaml
route:
  receiver: "slack"
  group_by: [instance, alertname]
  group_wait: 10s # 最初のアラートが来て10秒待ってから通知
  group_interval: 5m # 同じアラートが5分以内に発生した場合はまとめて通知
  repeat_interval: 30m # 30分ごとにリマインド

receivers:
  - name: "slack"
    webhook_configs:
      - url: "https://{api_gateway_id}.execute-api.{aws_region}.amazonaws.com/{stage}/alerts"
        send_resolved: true # アラートが解消された場合も通知
```

### 3-3. Step Functions

- AlertManager からのリクエストを受け取り、Lambda を順次実行するワークフローを管理します。
  - `severity`の値に応じて発火するバックエンドの Lambda を分岐させています。

![](/images/nb/oncall_state.png =600x)

### 3-4. Lambda（Python で実装）

各 Lambda の役割は以下の通りです：

- **ReceiveAlerts**
  - API Gateway からのリクエストを受け取り、`severity`の値を返す
  - `DynamoDB`からオンコール担当者の電話番号を取得し、以降の Lambda に引き渡す
- **PhoneCall**

  - `Twilio`の API を利用して電話通知を実施
  - さらに API Gateway のエンドポイントを叩いて電話の発信を行う
  - 電話が繋がった場合は`success`、繋がらなかった場合は`fail`、電話をかける必要のないプロダクトは`skip`を返す
  - 誰かが電話に出るまで、DynamoDB から取得した電話番号のリストを基に電話をかける処理をループします。

- **SlackNotification / SlackAlert**
  - [SlackのSDK](https://docs.slack.dev/tools/python-slack-sdk/)経由でアラート通知を実行する

### 3-5. 通知イメージ

- エンジニア全員が参加している、クリティカルな障害を検知する Slack チャンネルへ通知しています。

![](/images/nb/slack.png =600x)

## 4. まとめ

今回はオンコール基盤のアーキテクチャについて、ざっくり紹介しました。
具体的な要件や実装について記述していませんが、コストを抑えたオンコール基盤の一例として参考になれば幸いです！
