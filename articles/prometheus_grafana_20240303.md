---
title: "[Prometheus,Grafana]インストール,ログイン,初期設定"
emoji: "😺"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["AWS","Prometheus","Grafana","EC2","監視"]
published: true
---

## 本記事を読み終わった時のゴール
- Prometheus,Grafanaとはどういうものかざっくり把握出来る
- ご自身の環境にPrometheus,Grafanaをインストール出来る事

## 前提
- 必要なAWS環境は設定済みの状態(今回はEC2インスタンスを使用)
- `Prometheus`と`Grafana`は同一インスタンスへインストール
- `Node Exporter`は別インスタンスへインストール
&nbsp;

## Prometheusのインストール方法
![](/images/prometheus_grafana/prometheus_logo.png)

- インストールコマンド
```bash
# LTS版をダウンロード https://prometheus.io/download/
wget https://github.com/prometheus/prometheus/releases/download/v2.45.3/prometheus-2.45.3.linux-amd64.tar.gz
```

- 圧縮ファイルの解凍
```bash
tar xvzf prometheus-2.45.3.linux-amd64.tar.gz
```

- `systemd`でprometheusを制御するためにサービスユニットファイルを作成
```bash:/etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus Server
Documentation=https://prometheus.io/docs/introduction/overview/
After=network-online.target

[Service]
User=root
Restart=on-failure
# ご自身の環境に合わせてパスを書き換えてください。
ExecStart=/home/ec2-user/prometheus-2.45.3.linux-amd64/prometheus --config.file=/home/ec2-user/prometheus-2.45.3.linux-amd64/prometheus.yml

[Install]
WantedBy=multi-user.target

```

- systemdに変更を認識させるためにデーモンを更新
```bash
sudo systemctl daemon-reload
```

- サービスの起動設定
```bash
sudo systemctl start prometheus
sudo systemctl enable prometheus
systemctl status prometheus
```

-  prometheusへアクセス
デフォルトのポート番号は`9090`のため、SGで穴あけ出来ているか確認する必要あり。
#### http://{ホスト名}:9090
![](/images/prometheus_grafana/prometheus_login.png)
&nbsp;

## Node Exporterのインストール方法
- インストールコマンド
```bash
# https://prometheus.io/download/#:~:text=556adf78030370c461d059c8b4375e4296472a3af6036d217c979f68bcd5cb4e-,node_exporter,-Exporter%20for%20machine
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
```

- 圧縮ファイルの解凍
```bash
tar xvzf node_exporter-1.7.0.linux-amd64.tar.gz
```

- `systemd`でNodeExporterを制御するためにサービスユニットファイルを作成
```bash:/etc/systemd/system/node_exporter.service
[Unit]
Description=Prometheus Server
Documentation=https://prometheus.io/docs/introduction/overview/
After=network-online.target

[Service]
User=root
Restart=on-failure
ExecStart=/home/ec2-user/node_exporter-1.7.0.linux-amd64/node_exporter

[Install]
WantedBy=multi-user.target
```
- systemdに変更を認識させるためにデーモンを更新
```bash
sudo systemctl daemon-reload
```

- サービスの起動設定
```bash
sudo systemctl start node_exporter
sudo systemctl enable node_exporter
systemctl status node_exporter
```

-  `Node Exporter`へアクセス
デフォルトのポート番号は`9100`のため、SGで穴あけ出来ているか確認する必要あり。
#### http://{ホスト名}:9100
![](/images/prometheus_grafana/node_exporter_login.png)

##  `prometheus`から`Node Exporter`のメトリクス確認
:::message
予め、`Node Exporter`側のインスタンスのSGルールでprometheus側のインスタンスからのインバウンドアクセスを許可しておく事。
:::

```bash:/home/ec2-user/prometheus-2.45.3.linux-amd64/prometheus.yml
# my global config
global:
  scrape_interval: 60s # Set the scrape interval to every 15 seconds. Default is every 1 minute.
  evaluation_interval: 60s # Evaluate rules every 15 seconds. The default is every 1 minute.
  # scrape_timeout is set to the global default (10s).

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          # - alertmanager:9093

# Load rules once and periodically evaluate them according to the global 'evaluation_interval'.
rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

# A scrape configuration containing exactly one endpoint to scrape:
# Here it's Prometheus itself.
scrape_configs:
  # The job name is added as a label `job=<job_name>` to any timeseries scraped from this config.
  - job_name: "prometheus"

    # metrics_path defaults to '/metrics'
    # scheme defaults to 'http'.

    static_configs:
      - targets: ["localhost:9090"]
      - targets: ["{node_exporterのIP}:9100"]
```

- PromQLの`up`メトリクスを確認(Prometheusが正常にメトリクスをスクレイピングできた状態かどうか)
  - 値が`1`のためスクレイピング出来ている。(値が`0`なら失敗)
![](/images/prometheus_grafana/up.png)


## Blackbox Exporterのインストール方法
- インストールコマンド
  - Prometheus,Grafanaをインストールしているサーバーが対象
```bash
# ref: https://prometheus.io/download/
wget https://github.com/prometheus/blackbox_exporter/releases/download/v0.25.0/blackbox_exporter-0.25.0.linux-amd64.tar.gz
```

- 圧縮ファイルの解凍
```bash
tar -zxvf blackbox_exporter-0.25.0.linux-amd64.tar.gz
```

- blackbox expoeterのデフォルト設定ファイルの作成
```bash
# ref: https://github.com/prometheus/blackbox_exporter/blob/master/example.yml
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: []  # Defaults to 2xx
      method: GET
      preferred_ip_protocol: "ip4" # defaultはipv6のため修正する。
```

- `systemd`でBlackboxExporterを制御するためにサービスユニットファイルを作成
```bash:/etc/systemd/system/blackbox_exporter.service
[Unit]
Description=Prometheus Server
Documentation=https://prometheus.io/docs/introduction/overview/
After=network-online.target
[Service]
User=root
Restart=on-failure
ExecStart=/home/{your_dir_pass}/blackbox_exporter-0.25.0.linux-amd64/blackbox_exporter --config.file=/home/{your_dir_pass}/blackbox_exporter-0.25.0.linux-amd64/monitor_website.yml
[Install]
WantedBy=multi-user.target
```
- systemdに変更を認識させるためにデーモンを更新
```bash
sudo systemctl daemon-reload
```

- サービスの起動設定
```bash
sudo systemctl start blackbox_exporter
sudo systemctl enable blackbox_exporter
systemctl status node_exporter
```

### prometheus側の設定ファイル変更
- 監視したいURLに関する設定を追記する。
- EC2インスタンスに関連づけているSGで9115番ポートにアクセスできるようInboundeで自身のIPを許可する。
```bash:~/prometheus-2.53.3.linux-amd64/prometheus.yml
### 追加分を抜粋
  - job_name: 'blackbox'
    metrics_path: /probe
    params:
      module: [http_2xx]  # Look for a HTTP 200 response.
    static_configs:
      - targets:
        - https://twitter.com/ # 監視したいURLを記載する。
        - https://www.youtube.com/
        - https://www.instagram.com/
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: 127.0.0.1:9115  # The blackbox exporter's real hostname:port.
```

- Prometheusサービスの再起動
```bash
sudo systemctl restart prometheus
```

## Grafanaのインストール方法
![](/images/prometheus_grafana/grafana-logo.png) 
- インストールコマンド
```bash
# https://grafana.com/grafana/download?pg=oss-graf&plcmt=hero-btn-1&edition=oss
# 最新バージョンのOSS版をインストール
sudo yum install -y https://dl.grafana.com/oss/release/grafana-10.3.3-1.x86_64.rpm
```

- `systemd`でサービスの起動
```bash
# root権限で起動
sudo systemctl start grafana-server

# 自動起動の設定
sudo systemctl enable grafana-server

# 設定が反映されているか確認
systemctl status grafana-server
```
- Grafanaへアクセス
デフォルトのポート番号は`3000`のため、SGで穴あけ出来ているか確認する必要あり。

#### http://{EC2のホスト名}:3000/login

- Grafanaへログイン
##### 初期ユーザー名:`admin`
##### 初期PW:`admin`
![](/images/prometheus_grafana/login_grafana.png)

- 初期パスワードの変更が求められるため変更する。
![](/images/prometheus_grafana/grafana_pw_change.png)

- ログイン完了
![](/images/prometheus_grafana/grafana_login.png)

## GrafanaでPrometheusにDataSourceとして接続
- GrafanaはPrometheusで収集したメトリクスを可視化,分析するためのツールで内部的にPrometheusと接続する必要がある。
![](/images/prometheus_grafana/grafana_data_source1.png)

- `Save&test`を押下し`Successfully`の文字が表示されれば設定完了。
![](/images/prometheus_grafana/grafana_data_source2.png)

## 補足
- 大分省略してますが、こんな感じのダッシュボードが見れます。
### node exporter
https://grafana.com/ja/grafana/dashboards/1860-node-exporter-full/
![](/images/prometheus_grafana/node_full.png)

### blackbox exporter
https://grafana.com/grafana/dashboards/13659-blackbox-exporter-http-prober/
![](/images/prometheus_grafana/blackbox.png)

## 完
