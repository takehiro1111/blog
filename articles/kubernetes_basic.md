---
title: "k8s超入門: 基本的なコンポーネントの概要解説"
emoji: "🎉"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Kubernetes","コンテナ"]
published: true
---

![](/images/kubernetes/logo.png =400x)

## 1.記事を書いた背景
業務でEKSの環境を構築しており、知識を補完,整理するために記事として残しています。

## 2.対象読者
- Kubernetes初学者,未経験者(自分みたいな)

### 書くこと
- イメージしやすい範囲でk8sコンポーネントの概要
  - 今の時点で深入りしてもよく分からんってなるので、概要レベルのみの記述です。
  - 手を動かして実際のデプロイ環境を作る際に細かい書き方とか機能を必要に応じて調べれば良い。

### 書かないこと
- 詳細レベルやプラグイン等の解説
- EKS,GKE等のクラウドプロバイダ特有の設定


## 3.Kubernetesの基本的なコンポーネントの全体像
![](/images/kubernetes/component.png =600x)
```md
Kubernetesクラスタ
├ コンポーネント
│  ├ Control Plane(Master Node)
│  │  ├ API Server
│  │  ├ Scheduler
│  │  ├ Controller Manager
│  │  └ etcd
│  └ Worker Nodes
│     ├ kubelet
│     ├ kube-proxy
│     └ Container Runtime
│
└ リソース(ユーザーが作るもの)
   ├ Deployment
   ├ Pod
   ├ Service
   ├ ConfigMap
   └ Secret
```
@[card](https://kubernetes.io/ja/docs/concepts/overview/components/)
@[card](https://kubernetes.io/docs/concepts/architecture/)

### 3-1.Control Plane(旧称: Master Node)
- クラスタ全体の状態を管理する。

#### 3-1-1.Cluster
![](/images/kubernetes/cluster.png =450x)
- 複数のノード(サーバー)をまとめてコンテナを管理・実行する集合体。
- ECSで言うとECSクラスタと同じ概念。
- 以下2種類のリソースで構成されている。
  - クラスタを管理する`コントロールプレーン`
  - アプリケーションを動かすワーカーとなるノード
@[card](https://kubernetes.io/ja/docs/tutorials/kubernetes-basics/create-cluster/cluster-intro/)

#### 3-1-2.API Server
> Kubernetesの中核である control planeはAPI server です。
> APIサーバーは、エンドユーザー、クラスタのさまざまな部分、および外部コンポーネントが相互に通信できるようにするHTTP APIを公開します。
- クラスタの全操作はAPI Serverを経由して行われる。
  - RESTでリソースの操作を提供する。
  - 認証・認可処理
  - etcdへのデータ永続化
  - 他のコンポーネント(Scheduler、Controller等)との調整

@[card](https://kubernetes.io/ja/docs/concepts/overview/kubernetes-api/)
@[card](https://findy-code.io/media/articles/technote-sanpo_shiho)
#### 3-1-3.Scheduler
> Kubernetesにおいて、スケジューリング とは、KubeletがPodを稼働させるためにNodeに割り当てることを意味します。
- Nodeに割り当てられていないPodを監視し、稼働させるべき最適なNodeを見つけ出す責務を担う。

**選定基準**
- リソース(CPU/メモリ)の空き状況
- Node/Podのアフィニティ/アンチアフィニティ
- Podの分散配置
- 各Nodeの状態(正常性)

これらを総合的に評価(スコアリング)して、最も適したNodeに配置します。

@[card](https://kubernetes.io/ja/docs/concepts/scheduling-eviction/kube-scheduler/)

#### 3-1-4.Controller Manager
> API サーバーを介してクラスタの共有状態を監視し、現在の状態を望ましい状態に近づけるよう変更を加える制御ループを指します。

**役割**
クラスタの状態を常時監視し、「あるべき姿(desired state)」と「現在の状態(current state)」の差分を検知して自動修正。
セルフヒーリング機能の中核を担うコンポーネント。

**具体例**
- Deployment: 「replica: 3」と定義 → Podが2つに減った → 自動で1つ追加
- Node: Nodeがダウン → 該当Node上のPodを別Nodeに再配置
- Service: Endpointの自動更新

**内部の主なController**
- ReplicaSet Controller: Pod数の維持
- Node Controller: Nodeの状態監視
- Endpoint Controller: ServiceとPodの紐付け

@[card](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/)

#### 3-1-5.etcd
> etcdは、分散システムやマシンクラスターからアクセスする必要があるデータを信頼性の高い方法で保存するための、強力な一貫性を備えた分散キーバリューストアです。

**役割**
k8sクラスタの全ての設定・状態データを保存する分散データベース。

**保存されるデータ**
- Deployment、Pod、Serviceの定義
- クラスタの現在の状態
- ConfigMap、Secretの内容
- Node情報

**特徴**
- 高可用性(複数台で冗長化)
- 強い一貫性(データの整合性保証)
- 全てのリソースの定義と状態がetcdに保存される

**感覚的に**
k8sクラスタの「唯一の真実の情報源(Single Source of Truth)」。etcdが壊れるとクラスタ全体が機能停止。

@[card](https://kubernetes.io/ja/docs/tasks/administer-cluster/configure-upgrade-etcd/)
@[card](https://etcd.io/)

### 3-2.Worker Nodes
![](/images/kubernetes/node.png =450x)
- Podを実行する物理/仮想マシン(ここもECS同様にEC2が実態になっている)
- 複数のPodを持つ

> すべてのKubernetesノードでは少なくとも以下のものが動作します。
> Kubelet: Kubernetesマスターとノード間の通信を担当するプロセス。マシン上で実行されているPodとコンテナを管理します。
> レジストリからコンテナイメージを取得し、コンテナを解凍し、アプリケーションを実行することを担当する、Dockerのようなコンテナランタイム。

#### 3-2-1.`kubelet`
> kubeletは、各ノード上で実行される主要な「ノードエージェント」です。
> kubeletは、ホスト名、ホスト名をオーバーライドするフラグ、またはクラウドプロバイダー固有のロジックのいずれかを使用して、
> ノードをAPIサーバーに登録できます。

- Node自体をクラスタに登録
- Podの起動・監視
  - Control Planeからの指示でPod起動(コンテナ管理)
  - Podの状態を監視・報告

#### 3-2-2.`kube-proxy`
> Kubernetes ネットワーク プロキシは各ノードで実行されます。
> これは各ノードの Kubernetes API で定義されたサービスを反映し、単純な TCP、UDP、SCTP ストリーム転送、
> または複数のバックエンド間でのラウンドロビン方式の TCP、UDP、SCTP 転送を実行できます。
- 言葉通り、Node上でネットワークの転送の責務を担っている。

**補足: Pod間ネットワーク(CNI)**
- 実際のPod間通信はCNI(Container Network Interface)プラグインが担当
- kube-proxyはServiceレベルの通信を制御
- EKSではAWS VPC CNIがデフォルトで使用される

@[card](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/)

#### 3-2-3.`Container Runtime`
- 実際にコンテナを起動・実行するソフトウェアのこと。
- 実際のコンテナ起動はContainer Runtimeが担当し、`kubelet`がそれを制御する
- ECSで例えると、Docker Engineになる(らしい)
  - Dockerfileを使わないということではない。
@[card](https://kubernetes.io/ja/docs/setup/production-environment/container-runtimes/)


### 3-3.Resource
#### 3-3-1.Deployment
![](/images/kubernetes/deployment.png =600x)
- アプリケーションのデプロイを実行・管理する機能(YAMLで定義されるやつ)
  - Pod数の維持、ローリングアップデート、ロールバック等を担当
  - Podが落ちたら自動で再起動(セルフヒーリング)
  - Nodeが故障しても別Nodeで自動的にPodを起動

**Deployment → ReplicaSet → Podの階層構造**
Deploymentは内部的にReplicaSetを作成・管理:
- **ReplicaSet**: 指定した数のPodレプリカを維持
- **Deployment**: ReplicaSetを管理し、ローリングアップデートやロールバックを実現

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: todo-api
spec:
  replicas: 3  # 3つのPodを維持
  selector:
    matchLabels:
      app: todo-api
  template:
    metadata:
      labels:
        app: todo-api
    spec:
      containers:
      - name: api
        image: todo-api:v1.0  # このイメージでPod起動
```
@[card](https://kubernetes.io/ja/docs/concepts/workloads/controllers/deployment/)

#### 3-3-2.Pod
![](/images/kubernetes/pod.png =450x)
- 1つ以上のコンテナをまとめた最小実行単位(ECSタスクみたいな)
@[card](https://kubernetes.io/ja/docs/tutorials/kubernetes-basics/explore/explore-intro/)

#### 3-3-3.Service
![](/images/kubernetes/service.png =450x)
- Podへの通信を振り分ける、クラスタ内のネットワーク機能。
  - 固定のアクセスポイント提供
    - PodはIPが変動する(再起動で変わる)ため、固定IP/DNS名を提供

  - 負荷分散
    - 複数のPodにトラフィックを振り分け
      - ラベルとセレクタを使用して一連のPodを識別する。
        - ラベルは、作成時またはそれ以降にオブジェクトにアタッチでき、いつでも変更可能。

  - Pod(アプリケーション)の公開範囲の制御
    - ClusterIP: クラスタ内部のみ
    - LoadBalancer: 外部公開(実際のLB作成)

**DNS解決(CoreDNS)**
- クラスタ内ではCoreDNSがService名をIPアドレスに解決
- 例: `http://todo-api:8080` のようにService名でアクセス可能
- Pod同士の通信を簡素化する重要なコンポーネント

![](/images/kubernetes/label.png =450x)

@[card](https://kubernetes.io/ja/docs/concepts/services-networking/service/)

#### 3-3-4.Namespace
- リソースを論理的に分離する仕組み
- 例: dev環境とprod環境を同一クラスタ内で分離
- デフォルトで以下のNamespaceが存在:
  - `default`: デフォルトのNamespace
  - `kube-system`: Kubernetesシステムコンポーネント用
  - `kube-public`: 全ユーザーからアクセス可能なリソース用

@[card](https://kubernetes.io/ja/docs/concepts/overview/working-with-objects/namespaces/)

#### 3-3-5.ConfigMap
- アプリケーションの設定情報を保存するリソースのこと。
- ECSタスクでも設定する環境変数のようなイメージ
  - 複数Podで同じConfigMapを使いまわせる。
  - ConfigMapのnameはDNSの命名規則に従う必要がある。

```yaml:例
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  DATABASE_URL: "postgres://..."
  LOG_LEVEL: "info"
---
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: app
    envFrom:
    - configMapRef:
        name: app-config  # ConfigMapを環境変数として注入
```
@[card](https://kubernetes.io/ja/docs/concepts/configuration/configmap/)

#### 3-3-6.Secret
- 機密情報(パスワード、トークン等)をBase64エンコードして保存する。
- Secretを利用することでアプリケーション側のコードで機密情報を含める必要がなくなる。
- アプリケーションのPodとは独立して作成できる。

:::message alert
デフォルトではBase64エンコードのみで暗号化されません。
Production環境ではetcdの暗号化や外部シークレット管理サービス(AWS Secrets Manager等)の利用を検討してください。
:::

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
data:
  password: aG9nZQ==  # "hoge"のBase64エンコード
# または stringData を使用する場合:
# stringData:
#   password: hoge  # 自動的にBase64エンコードされる
```
@[card](https://kubernetes.io/ja/docs/concepts/configuration/secret/)

## まとめ
久々にインフラ学んでるな〜という感覚です。
ただ、書きながら感じたこととして結局アプリケーションをデプロイしたり、Production環境の運用までしないと全体像として理解した感覚にはなりそうにないですね。

千里の道も一歩からということで地道に理解しつつ、最終目標としてはマイクロサービス上でフロント,バック,インフラを横断的に触りながらアプリケーション開発したいなと思っています。

適度にインプットしつつ、次のステップはEKSを公式Moduleを使用せず各構成要素が見えやすい形式で構築しようと思います。
最終的には今個人開発している高機能のTodoアプリをEKSにデプロイしてCI/CDも実装したい。

## 参考
@[card](https://kubernetes.io/docs/tutorials/)
@[card](https://kubernetes.io/ja/docs/home/)
@[card](https://docs.aws.amazon.com/ja_jp/eks/latest/userguide/what-is-eks.html)
@[card](https://thinkit.co.jp/article/17453)
@[card](https://thinkit.co.jp/article/18240)

