---
title: "[Terraform/AWS/Github]GithubActionsとAWSの連携"
emoji: "📚"
type: "tech" # tech: 技術記事 / idea: アイデア
topics:  ["Terraform","aws","IaC","Github","GithubActions"]
published: true
---
![](/images/actions_s3/actions_logo.png =450x)

## 本記事を読み終わった時のゴール
- GithubActionsでAWS APIに処理するために必要な権限周りの設定を行得る状態。
 今回は、例としてローカルからS3バケットにファイルを置く処理を実行します。

&nbsp;

## 1.権限周りの設定(AWS側)
### ①Open ID ConnectでIDPをAWS側へ設定

```hcl:./modules/iam/oidc/main.tf
resource "aws_iam_openid_connect_provider" "default" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

   thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
    ]
}

```

```hcl:./modules/iam/oidc/output.tf
output "oidc_arn" {
    value = aws_iam_openid_connect_provider.default.arn
}

```

```hcl:./security.tf
module "oidc" {
  source = "./modules/iam/oidc"
}

```

https://docs.aws.amazon.com/ja_jp/IAM/latest/UserGuide/id_roles_providers_create_oidc.html
https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider

### ここで少し深掘り
- `OIDC(OpenID Connect)`とは？
以下の図を参照。
OIDCに関して調べてみると様々な表現があり細かい表現の厳密性は保証できませんが、大枠のイメージとして見ていただければと思います。
内容的には、今回の処理する構成に合わせています。
![](/images/actions_s3/idp_actions.png)

https://www.authlete.com/ja/resources/videos/20200131/01/
https://www.nri-secure.co.jp/glossary/openid-connect#:~:text=OpenID%20Connect%E3%81%A8%E3%81%AF%E3%80%81%E3%82%B5%E3%83%BC%E3%83%93%E3%82%B9,%E3%81%8C%E5%8F%AF%E8%83%BD%E3%81%AB%E3%81%AA%E3%82%8A%E3%81%BE%E3%81%99%E3%80%82
https://solution.kamome-e.com/blog/archive/blog-auth-20221108/

- `IDフェデレーション`とは？
> ID フェデレーションは、ユーザーを認証し、リソースへのアクセスを許可するために必要な情報を伝達することを目的とした、2 者間の信頼システムです。
> このシステムでは、ID プロバイダー (IdP) がユーザー認証を担当し、サービスやアプリケーションなどのサービスプロバイダー (SP) がリソースへのアクセスを制御します。
> 管理上の合意と設定により、SP は IdP によるユーザーの認証を信頼し、IdP から提供されたユーザーに関する情報を利用します。

#### 今回のケースだと、`IDP→GithubActions`,`SP→AWS`になる。

https://aws.amazon.com/jp/identity/federation/#:~:text=ID%20%E3%83%95%E3%82%A7%E3%83%87%E3%83%AC%E3%83%BC%E3%82%B7%E3%83%A7%E3%83%B3%E3%81%AF%E3%80%81%E3%83%A6%E3%83%BC%E3%82%B6%E3%83%BC%E3%82%92,%E9%96%93%E3%81%AE%E4%BF%A1%E9%A0%BC%E3%82%B7%E3%82%B9%E3%83%86%E3%83%A0%E3%81%A7%E3%81%99%E3%80%82
https://hogetech.info/security/sso/federation

- `thumbprint`とは？
> IAM では、外部 ID プロバイダー (IdP) が使用する証明書に署名した最上位中間認証局 (CA) のサムプリントが必要です。
> 拇印(thumbprint)は、OIDC 互換 IdPの証明書を発行するために使用された CAの 証明書の署名です。
https://docs.aws.amazon.com/ja_jp/IAM/latest/UserGuide/id_roles_providers_create_oidc_verify-thumbprint.html

#### ちなみに、今回の`thumbprint`の設定は以下を参照しました。
https://github.blog/changelog/2023-06-27-github-actions-update-on-oidc-integration-with-aws/
https://tech.route06.co.jp/entry/2023/06/29/181610


- `url`の値が固定値になるのは何故？
以下、ChatGPT大先生の見解です。
個人的に納得する材料が欲しかったので見解をいただきました。

> GithubActionsをIDPとして設定する場合は、`https://token.actions.githubusercontent.com`という固定値で設定する必要があります。
> これは、GitHub Actionsが提供する標準化されたエンドポイントであり、GitHub Actionsによる認証情報（IDトークン）を発行するために使用されます。
> このエンドポイントはGitHubによって管理され、GitHub Actionsを使ってAWSリソースにアクセスするための認証に必要なIDトークンを提供します。

- `client_id_list`の値が`["sts.amazonaws.com"]`の理由
以下もChatGPT大先生の見解です。
個人的に納得する材料が欲しかったので見解をいただきました。

>`sts.amazonaws.com`は、AWS Security Token Service (STS) のサービスエンドポイントです。
> AWS STSは、一時的なセキュリティ認証情報を提供するサービスであり、この認証情報はAWSリソースへのアクセスに使用されます。
> GitHub ActionsからAWSへの認証プロセスでは、GitHub ActionsがOIDCプロバイダとして機能し、AWS STSをクライアントとして利用して一時的なセキュリティ認証情報を発行します。
> client_id_listにsts.amazonaws.comを含めることで、このOIDCプロバイダ（GitHub Actions）がAWS STSに対して認証情報を提供できることを示しています。

> OIDCの仕様では、IDトークンの受信者（audience）を指定することができます。
> この場合、sts.amazonaws.comはIDトークンの受信者として指定され、AWS STSがそのトークンを受け取るべき対象であることを意味します。
> これにより、IDトークンが特定のサービス（この場合はAWS STS）向けに発行されたことが確認できます。

:::message alert
値は`sts.amazonaws.com`です。
ポリシーの`Action`要素を書く際の書き方と異なるため、癖で間違えないように注意が必要です。
私は血迷って少し沼にハマりました。

(誤)sts:amazonaws.com
(正)sts.amazonaws.com
:::
&nbsp;

### ②IAMロールの設定
```hcl:./security.tf
# GithubActions用のIAMロール,ポリシー ---------
// IAMロール,信頼ポリシーの設定
resource "aws_iam_role" "deploy_github_actions" {
  name = "deploy-github-actions"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
        {
            Action = "sts:AssumeRoleWithWebIdentity",
            Effect = "Allow"
            Principal = {
                Federated = module.oidc.oidc_arn
            },
            Condition = {
              StringEquals = {
                "token.actions.githubusercontent.com:aud" = "sts:amazonaws.com"
              },
              StringLike = {
                "token.actions.githubusercontent.com:sub" = [
                  "repo:{your_Github_Organizations_name}/{your_repository_name}:*",
                  "repo:{your_Github_user_name}/{your_repository_name}:*",
                ]
              }
            }
        }
    ]
  })
}

// 許可ポリシーの設定(S3のフルアクセスを許可)
data "aws_iam_policy_document" "deploy_github_actions" {
  statement {
    effect = "Allow"
    actions = [
      "s3:*",
      "s3-object-lambda:*"
    ]
    resources = ["*"]
  }
}

// IAMロールと許可ポリシーを関連付け
resource "aws_iam_role_policy" "deploy_github_actions" {
  name = aws_iam_role.deploy_github_actions.name
  role = aws_iam_role.deploy_github_actions.name
  policy = data.aws_iam_policy_document.deploy_github_actions.json
}

```
https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document
https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy
https://dev.classmethod.jp/articles/allowing-assumerole-only-for-specific-repositories-and-branches-with-oidc-collaboration-between-github-actions-and-aws/
&nbsp;

## 2.GithubActiuonsでworkflowの作成
- mainブランチにpushされた事をトリガーにAssumeRoleでリポジトリ内のサブディレクトリ以下のファイルをS3バケットへコピーする処理です。
```yml:./github/workflows/aws_s3_ls.yml
name: CP to S3 Tokyo Region

on:
  push:
    branches:
      - main
    paths:
      - '.github/workflows/*'
      - '.github/actions/*'
      - '**/*.tf'
  workflow_dispatch:

jobs:
  deploy:
    name: Get from S3 in Tokyo
    runs-on: ubuntu-latest

    permissions:
      id-token: write
      contents: read

    steps:
      - name: Checkout repository
        uses: actions/checkout@v3
      
      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-region: ap-northeast-1
          role-to-assume: arn:aws:iam::{your_aws_account_id}:role/deploy-github-actions # S3アクセス権限を持つIAMロール
          role-session-name: GitHubActionsSession 
          #CloudTrailログ等の監査ログでどのセッションがどの操作を行ったのかを追跡するために設定。

      - name: CP bucket list to S3
        id: cp
        working-directory: ./test_s3
        run: |
          aws s3 ls
          aws s3 mb s3://test-actions-20240211
          aws s3 cp ./ s3://test-actions-20240211 --recursive
          aws s3 ls s3://test-actions-20240211
        shell:
          bash
```
https://docs.github.com/ja/actions/learn-github-actions/understanding-github-actions
https://github.com/marketplace/actions/configure-aws-credentials-action-for-github-actions
&nbsp;


## 3.ワークフローの実行
### 以下２パターンで実行可能。
#### ①ローカルから直接`push`を行う場合
- ローカルで変更をcommitし、mainブランチへ`push`すると自動で実行されます。
```bash
git add .
git commit -m {メッセージ}
git push origin main
```
:::message
実際に`main`ブランチへ直接変更するpushする事は推奨されません。
基本的には`feature/*`等のブランチを切ってプルリクエストを上げてからmainにマージします。
:::
&nbsp;

#### ②他ブランチから main ブランチへのプルリクエストがマージされた場合。
- プルリクエストがmainブランチにマージされた際に処理が走ります。
または、以下のようにプルリクエストに条件を指定した設定でも同様に処理が実行されます。

```yml
on:
  pull_request:
    branches:
      - main
    types: [closed]

jobs:
  deploy:
    runs-on: ubuntu-latest
    if: github.event.pull_request.merged == true
```
&nbsp;

#### ③手動で画面上からポチッと実行します。
- `workflow_dispatch`を設定しているため、画面上からも手動で実行可能です。
![](/images/actions_s3/workflow_dispatch.png)
&nbsp;

## 4.実行結果
- 以下の画面からワークフローが成功している事が確認できました。
![](/images/actions_s3/finish.png)
&nbsp;

## 公式ドキュメント
https://docs.github.com/ja/actions

## 完