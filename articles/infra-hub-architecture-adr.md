---
title: "社内向けアプリケーションを個人開発してリリースした話"
emoji: "🛠️"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["AWS", "Next.js", "SRE", "Lambda", "Auth.js"]
published: false
---

## この記事で書くこと

社内(副業先)向けに作った`Infra-Hub`というアプリケーションの設計判断を、備忘録も含め記述します。

- なぜ作ることになったか
- AWS の全体構成と判断したこと
  - 実行基盤に Lambda + Function URL + CloudFront を選んだ理由
  - 認証を Auth.js + Google OIDC にした理由
  - 認可を IAM ロールとハブ & スポークで行う理由
  - DB を持たない理由
  - Next.js の単一アプリにし、FE と BE を分けない理由
- 許容したリスクと監視
- 構成を見直す条件
- 今後の展望

## なぜ作ることになったか

コスト削減の手段として、本番以外のインフラリソースは使っていない時間は止める取り組みをしたいと考えた事がきっかけです。


AWSだと、EventBridge Scheduler の定時起動停止で簡単に実現できます。
ただ、社内の開発組織では正社員や私のような業務委託で参画しているエンジニアも居たり、ビジネス職の方がバイブコーディングで開発しているプロダクトも存在します。


そのため、業務時間外で環境を使いたいケースがあるという話もあり、自動での起動停止だけでなくAWSアカウントに入らなくても何らかの方法で手軽に手動で起動停止する仕組みもセットで必要という話をCTOとしました。


それがきっかけでUIから起動停止できたら良いのではと考え、命名は今後他のインフラや開発周辺のPlatformに関するトイルも解消できるようなアプリケーションにしたいと思いInfra-Hubと名付けて開発するに至りました。

## 全体構成

![infra-hub の AWS 構成](/images/infra_hub/architecture.png)

利用者の入口は、全社員が使っている別の社内アプリケーションのサイドバーに Infra-Hub への項目を追加する形にしました。
普段使っているアプリから辿れるので新しい URL を覚えてもらう必要がなく、Google の OAuth クライアントもそのアプリと共用しているため、同じアカウントでそのままサインインできます。

### 判断したこと
1. 実行基盤の選定
```md
- Lambda（コンテナイメージ + Lambda Web Adapter）+ Function URL + CloudFrontにし、常時稼働するコンピュートやネットワークリソースに依存しない
  - 本記事を公開する前にLambda Web FunctionsがGAされたため、新しく作る場合はLambda Web Adapterを意識する必要性はないです。
  - Function URL は認可 NONE にし、CloudFront が origin へ付与する `x-origin-verify` ヘッダをアプリ側（proxy.ts）で検証する。CloudFront を通らない直アクセスは 403 で弾く。
```

2. 認証
```md
- Auth.js + Google OIDCでアプリで直接受ける。
  - 許可した Workspace ドメインかつメール検証済みのアカウントだけサインインでき、セッションは JWT（12 時間）
  - Cognito + Google Workspace（外部 IdP）の SAML 認証で認証をインフラにオフロードする方向も検討したが、
    Workspace側の設定が面倒なため、他の社内Webアプリで運用中のOIDCの方が良いとCTOと合意した。
```
  
3. 認可
```md
- IAMロールで行い、マルチアカウントでの認可はハブ & スポーク。ハブの Lambda 実行ロールが、各 TEST アカウントのロールを AssumeRole する。
  - 起動・停止などの変更系を `infra-hub:managed=true` タグ付きリソースだけに許可し、本番やその他リソースは IAMで対象にしないことで分離する。
```
  
5. DBを持たない。
```md
- 操作ログは誰が・いつ・何を・結果 をCloudWatch Logs に残す
  - 状態は特定のタグを付与したリソースの Describe API から取得する。
  - ブラウザのタブを表示している間はポーリングで状態を更新する。
    - 起動・停止の途中は 5 秒、安定時は 60 秒ごと。タブが非表示の間は止め、タブに戻った時に再取得する（SWR の `refreshWhenHidden` / `revalidateOnFocus` の既定値）。
  - 今後、機能追加する際にDBが必要なケースが発生する場合は他の社内Webアプリで使用しているAuroraへRDS Proxyを用いて接続する。
```

6. Next.js（App Router）を用いてFEとBEを分割しない設計にした。
```md
- Route Handler が APIを叩き、同じコードベースに画面を置く。
  - 現在考えている範囲ではAPIでもインフラ層の利用がメインになり、厳密にアプリケーションアーキテクチャを設計する必要性がないため。
```

以降、これらの判断をそれぞれ見ていきます。

## 判断1. 実行基盤は Lambda + Function URL + CloudFront

理由はコストです。

利用が 1 日数回・数名のツールに、ECS Fargate や App Runner のような常時課金のコンピュートや ALB の固定費を払う理由がありません。
Lambda は実行時間だけの課金で、待機中は 0 になります。

社内ユーザー & 用途的にもパフォーマンスを求めるアプリケーションではないため、コールドスタートは許容しています。


### 他に検討した構成
| 案 | 却下理由 |
|---|---|
| ECS Fargate + ALB | 常時課金と ALB 固定費。利用頻度に見合わない |
| App Runner | 最小インスタンスの常時課金が残る |
| Function URL を OAC（AWS_IAM）で保護 | POST のたびにブラウザ側で本文のハッシュをヘッダに付ける必要がある。代わりに CloudFront が付ける `x-origin-verify` ヘッダをアプリで検証する |

### Lambda Web Adapter で Next.js をそのまま動かす

Lambda 向けにアプリを書き換えたくなかったので、Lambda Web Adapter（LWA）を使っています。
コンテナイメージに LWA を拡張として同梱すると、Function URL のリクエストを HTTP として `PORT` に橋渡ししてくれるので、Next.js の standalone サーバをそのまま起動できます。

```dockerfile
FROM public.ecr.aws/awsguru/aws-lambda-adapter:1.0.1 AS lwa

FROM node:22-bookworm-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production PORT=8080 HOSTNAME=0.0.0.0
COPY --from=lwa /lambda-adapter /opt/extensions/lambda-adapter
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
USER node
CMD ["node", "server.js"]
```

Lambda Web Adapter は `/opt/extensions/` に置いた Lambda 拡張（Lambda Extension）として動きます。
Lambda の実行環境は起動時に `/opt/extensions/` 配下のファイルを拡張として起動し、Function URL から来たリクエストを HTTP に変換して `PORT` の Next.js へ渡します。
この仕組みは Lambda の実行環境にしかないため、同じイメージをローカルで `docker run` すると `/opt/extensions/lambda-adapter` はただのファイルとして置かれたままになり、`CMD` の `node server.js` だけが動いて Next.js が 8080 番で直接リクエストを受けます。
どちらでも Next.js 側は「8080 番で HTTP を受ける」だけで、Lambda 専用のハンドラやエントリポイントをコードに持っていません。
Lambda 向けの差分が拡張ファイル 1 つに閉じているため、Lambda 用に Dockerfile を分けたりハンドラを書いたりせず、普通の Web アプリと同じ Dockerfile のままで Lambda でもローカルでも動きます。

### CloudFront 経由であることの検証: `x-origin-verify` ヘッダ

![1 リクエストの通り道](/images/infra_hub/auth.png)

Function URL の認可は `NONE` です。
代わりに CloudFront が origin へのリクエストに共有シークレットのヘッダ（`x-origin-verify`）を付け、アプリ側の `proxy.ts`（Next.js 16から`middleware` から改称された規約）が全パスで検証し、一致しなければ 403 を返します。

Function URL を `AWS_IAM` にして CloudFront の OAC（Origin Access Control）で保護する案も検討しました。
CloudFront が origin へのリクエストに AWS の署名を付け、署名の無い直アクセスは Lambda が拒否する方式です。
ただし、この方式で POST を通すには、ブラウザが毎回リクエスト本文のハッシュを計算して `x-amz-content-sha256` ヘッダに入れる必要があります。
CloudFront はこのヘッダを作ってくれないため、画面の `fetch` に計算処理を足すことになります。
IAM 署名で守る案はブラウザ側に余計な実装が要るので、代わりに CloudFront が origin へ付ける固定の共有シークレットヘッダ（`x-origin-verify`）をアプリで照合する方式にしました。
シークレットの値は Secrets Manager に置き、アプリが起動時に取得します。

検証の流れは次のとおりです。

1. 共有シークレットの値は Terraform が生成し、CloudFront の origin のカスタムヘッダと Secrets Manager の両方に同じ値を入れる
2. Lambda には Secrets Manager のシークレット名だけを環境変数で渡す
3. アプリは最初のリクエストで Secrets Manager から値を取得し、プロセスが生きている間はメモリに保持する
4. 以降は全リクエストで、届いた `x-origin-verify` ヘッダの値とメモリ上の値を比較し、一致しなければ 403 を返す

## 判断2. 認証は Auth.js + Google OIDC

`proxy.ts` で Auth.js のセッションを見ます。
無ければ画面は `/signin` へリダイレクト、API は 401 を JSON で返します。
API を HTML のリダイレクトにしないのは、画面側が `fetch` で `/api/...` を呼んでいるためです。
未認証の API がサインイン画面へのリダイレクト（302 + HTML）を返すと、`fetch` はリダイレクトを黙って追いかけ、サインイン画面の HTML を 200 で受け取ります。
これを JSON として読もうとして失敗し、「未認証」とは分からないエラーになります。
そのため API だけは 401 と JSON（`{"code":"UNAUTHORIZED",...}`）を返し、クライアントが「未認証」と判定してサインインへ誘導できるようにしています。

```ts
export default async function proxy(request: NextRequest, event: NextFetchEvent) {
  // CloudFront を経由しない直アクセスは、認証フローや静的アセットも含めて全パスで遮断する
  if (!(await isTrustedOrigin(request.headers))) {
    return jsonError(HTTP_STATUS.FORBIDDEN, "FORBIDDEN", "アクセスが許可されていません");
  }
  if (AUTH_EXEMPT_PATH.test(request.nextUrl.pathname)) {
    return NextResponse.next();
  }
  return (await middleware)(request, event);
}
```

サインインは Google OIDC に直結しています。
`hd` パラメータで Workspace のアカウントを優先表示しますが、Google 側の設定には頼らず、アプリ側のコールバックでも「`hd` が許可ドメインと一致し、かつ `email_verified` が true」を確認します。

```ts
export const isAllowedProfile = (profile, allowedDomain) =>
  profile?.email_verified === true && profile.hd === allowedDomain;
```

当初は Cognito User Pool + Google Workspace（外部 IdP）の SAMLで、認証をインフラにオフロードする方向でした。
Workspace 側の設定が面倒なことに加え、社内の別 Web アプリでも同様にOIDCで認証していたため、そちらと合わせる方向で合意しました。

## 判断3. 認可は IAM ロールとハブ & スポーク

ハブアカウントの Lambda 実行ロールが、各 TEST アカウントのスポークのIAMロールをAssumeRoleします。
スポーク側はハブのロールだけを信頼する設定のみで良いため、アカウントを追加するときも Terraform のモジュールを1つ足すだけで運用が楽にしたいため採用しました。

一部のアカウントで取得に失敗しても残りは表示し、失敗したアカウントを画面で知らせます。
1 アカウントの不具合で全体が見えなくならないようにしています。

Route Handler は対象外アカウントへの要求を拒否し、スポークアカウントのロールを AssumeRole して AWS API を呼びます。
スポーク側のロールは、読み取り系は無制限、変更系はタグ `infra-hub:managed=true` の付いたリソースだけに限定しています。

```hcl
statement {
  sid = "MutateManagedResources"
  actions = [
    "ec2:StartInstances", 
    "ec2:StopInstances",
    "rds:StartDBInstance", 
    "rds:StopDBInstance",
    "rds:StartDBCluster", 
    "rds:StopDBCluster",
    "ecs:UpdateService",
  ]
  resources = ["*"]
  condition {
    test     = "StringEquals"
    variable = "aws:ResourceTag/infra-hub:managed"
    values   = ["true"]
  }
}
```

タグを付けるのは TEST 環境のリソースだけなので、本番リソースはそもそも操作できません。
「UI 側で本番を除外する」ではなく「IAM で変更できない」にしています。

## 判断4. DB を持たない

RDS は最小構成でも月額の固定費が発生します。
このアプリが持つべき状態は「AWS リソースの今の状態」だけで、それは AWS API が正です。
写しを DB に持つと二重管理になるうえ、費用だけ増えます。
RDS / DynamoDB にリソース状態を持つ案は、現状の機能では API の結果が正となるため不要と判断しました。

DB を無くした結果として必要になるものは、それぞれ別の手段で足りました。

- セッション管理
  - Auth.js の JWT（12h）
- 監査証跡
  - CloudWatch Logs への JSON 出力

### 監査ログ

DB が無いので、操作ログは構造化 JSON で CloudWatch Logs に出しています。
誰が（メールアドレス）・いつ・どのリソースに何をして・結果がどうだったか、を 1 行で残します。

### 画面の状態はポーリングで追う

リソースの状態は、タグ `infra-hub:managed=true` の付いたリソースを Describe API で取得して画面に出します。
ブラウザのタブを表示している間は SWR でポーリングし、起動・停止の途中は 5 秒、安定時は 60 秒ごとに更新します。
タブが非表示の間は止め、タブに戻った時に再取得します（`refreshWhenHidden` / `revalidateOnFocus` の既定値）。

今後、機能追加で DB が必要になった場合は、他の社内 Web アプリで使用している Aurora へ RDS Proxy を用いて接続する想定です。

## 判断5. Next.js の単一アプリにし、FE と BE を分けない

![アプリの内側は 3 段だけ](/images/infra_hub/layers.png)

Go などでバックエンドを別サービスに分ける案もありましたが、採りませんでした。
理由は 2 つです。

- 共通のUIアプリケーションの側面が強いため、ドメインが薄い。
- 「一覧・起動・停止」の 3 つしかなく、アプリ固有の永続モデルも無い。
  - バックエンドを分けると、API 契約と型の二重定義を維持するコストだけが増えて得るものがない。
- AWS API の状態が正で、アプリは AWS API を呼んで整形して返すだけ。
  - リポジトリ層・DTO・ユースケース層のような翻訳の層を置くと、読む量が増えるだけになる。
  - インフラ層に対する処理がメインのため、責務を意識しなくて良いのではと感じた。

そのため、層を切って階層化せず、次の 3 段だけにしています。

1. `app/api`: 入口。Route Handler で入力検証（zod）と認可
2. `src/features/<機能>`: 操作の組み立て。例えば `start-stop` には一括操作の段階実行や部分失敗の扱いが入る
3. `src/lib/aws-client`: AWS SDK の薄いラッパー。AssumeRole 済みのクライアントで呼ぶ

一括操作の段階実行は、依存の下にあるものから立ち上げ、上から落とす順にしています。

```ts
// 起動: RDS -> EC2 -> ECS / 停止: ECS -> EC2 -> RDS
export const phaseOrder: Record<ResourceAction, readonly ResourceKind[]> = {
  start: ["rds", "ec2", "ecs"],
  stop: ["ecs", "ec2", "rds"],
};
```

### AI エージェントと一緒に開発する前提
モノレポで単一言語にすることで、AI エージェントがコード全体を一度に読んで変更できるようにしたかったことです。

層をまたぐ変更で複数ファイルの整合を取らせるより、機能単位（`src/features/<機能>`）でまとまっている方が、今回のケースだと生成もレビューもやりやすいと感じています。

## 許容したリスク

DB を持たず Lambda で動かす以上、いくつかの制約は受け入れています。

| 制約 | 内容 | 対応 |
|---|---|---|
| 実行時間の上限 | Lambda の timeout は 55 秒。CloudFront の origin 読み取り 60 秒より短くし、打ち切りを CloudFront 側の 504 ではなく Lambda 側のログに残す | 一括操作は段階実行。Duration の p90 が 40 秒を超えたらアラーム |
| セッション失効の遅れ | JWT のため、Workspace から削除されたユーザーも最長 12 時間は操作できる | MFA と退職時のアカウント停止は Workspace 側で担保 |
| 利用者単位の権限を持てない | DB が無いため「特定の開発者だけ許可する」判定元をアプリ内に持てない | 必要になった時に判定元（Google グループなど）を別途決める |
| コールドスタート | 初回アクセスは数秒かかる | 社内ツールとして許容 |


## 監視
基盤の監視はCloudWatch Alarms を 4 つ置き、EventBridge → SNS → Slack に通知しています。

| アラーム | 条件 | 意味 |
|---|---|---|
| Lambda Errors | 5 分間に 1 回以上 | 利用者の操作が途中で失敗している |
| Lambda Throttles | 5 分間に 1 回以上 | 同時実行数の上限で拒否。利用者には 5xx |
| Lambda Duration p90 | 40 秒超 | timeout で打ち切られる前兆 |
| Function URL 5xx | 5 分間に 1 回以上 | 利用者にエラー画面が出ている |

## 構成を見直す条件
今後どうなるかは分かりませんが、次のいずれかに当たるなら構成を再検討する想定です。

| 機能追加の種類 | 例 | 対応 |
|---|---|---|
| アプリ固有の状態を持つ | 利用者ごとの権限、操作の予約や承認フロー、設定の保存 | DB の追加を検討 |
| ドメインが厚くなる | 複数リソースにまたがる不変条件、業務ルールの分岐 | 層の追加や責務の分割を検討 |
| 1 リクエストで長時間の処理 | 55 秒を超える処理 | Step Functions や SQS などの非同期実行へ切り出す |
| 監査要件が厳しくなる | 上場準備などで操作ログの改ざん防止や長期保管、承認の記録が求められる | 操作ログの保存先と保持期間の見直し、承認フローの追加（DB が必要になる）を検討 |

## 今後の展望

Infra-Hub はDEV環境のインフラリソースの起動停止機能から始めましたが、SREやPlatform Engineeringの文脈で組織貢献できるよう、
主体的に問題発見から行い、必要に応じて機能を追加していく予定です。

