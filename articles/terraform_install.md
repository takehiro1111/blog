---
title: "[Terraform/AWS]インストール,初期設定"
emoji: "🐙"
type: "tech" # tech: 技術記事 / idea: アイデア
topics:  ["Terraform","aws","IaC","SRE","インフラエンジニア"]
published: true
---
![](/images/terraform_logo.png)

## 本記事を読み終わった時のゴール
- Linux/Macの何れかの環境にTerraformをインストール出来る事。
- Terraformの主要な管理コマンドをざっくり把握した状態。
- AWS CLI,HCLでAWS APIを呼び出せるよう適切に認証情報を設定できる事。

&nbsp;

## 目次
1. Terraformの概念
2. 実際にTerraformをインストールする(Mac/Linux)
3. Terraformの主要な管理コマンド
4. CLI,HCLでAWS APIを呼び出せるよう認証情報の設定
&nbsp;

## 本編
## 1. Terraformの概念
#### Terraformとは？
米企業の Hashicorp 社が開発したIaCを実現するためのツールです。
`HCL`という独自の言語を用いてインフラ環境を構築します。

#### メリット
- マルチプロバイダのサポート(AWS,Azure,GCP,オンプレミス,Github等)
- 可読性が高い。(AWS CloudFormationより比較的読みやすい。)
- バージョン管理が容易。
- コードを用いて管理する事で操作方法の属人化を解消出来る。(Iac全般)

#### デメリット
- 経験者が少ない為、エンジニア市場での経験者の採用に苦戦しやすい。
- 細かいリソースの操作をサポートしていない。
  (例:EC2,RDSでは、`作成` or `削除`しか出来ず停止をサポートしていない。)
&nbsp;

## 2. 実際にTerraformをインストールする(Mac/Linux)
#### 前提
今回は Mac並びにLinux(AmazonLinux2)の環境下でインストールします。
terraformコマンドを直接インストールする方法もありますが、実際の実務では複数人で開発する事を想定して
tfenvをインストールしてterraformを扱います。

#### tfenvとは？
Terraformのバージョンの切り替えを容易に行えるツールです。
実務ではチームで開発する事から、各個人が異なるバージョンを使用していると互換性の面で予期しないエラーが発生する可能性が高いです。
バージョンを統一するためにもtfenvでの管理が必要です。

#### インストール実践
```bash:MacOSの場合
# HomeBrewのインストール
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
brew -v

# MacOSへtfenvをインストール
brew install tfenv
# バージョンが表示されていればインストール成功。
tfenv -v
# インストール可能なterraformコマンドのバージョン一覧を表示。
tfenv list-remote
# list-remoteで表示された内、特定バージョンのterraformコマンドをインストール。
tfenv install 1.6.1
# インストールしたバージョンを使用するよう適用。
tfenv use 1.6.1
# 現在適用しているterraformコマンドのバージョン確認。
terraform version
# ローカルにインストールされているterraformコマンドのバージョン確認。
tfenv list

```

```bash:LinuxOSの場合
# パッケージ管理ツールでgitをインストール
sudo yum install git
git -v
# Githubのリポジトリのコードやファイルを複製し、ユーザーのホームディレクトリに.tfenvファイルを作成する。
git clone https://github.com/tfutils/tfenv.git ~/.tfenv
# tfenv及びterraformコマンドが使用できるようにシンボリックリンクで/usr/local/binにパスを通す。
echo $PATH
sudo ln -s ~/.tfenv/bin/* /usr/local/bin
# コマンドが使用できるか確認。
tfenv -v
# インストール可能なterraformコマンドのバージョン一覧を表示。
tfenv list-remote
# list-remoteで表示された内、特定バージョンのterraformコマンドをインストール。
tfenv install 1.6.1
# インストールしたバージョンを使用するよう適用。
tfenv use 1.6.1
# 現在適用しているterraformコマンドのバージョン確認。
terraform version
# ローカルにインストールされているterraformコマンドのバージョン確認。
tfenv list

```
&nbsp;

## 3.Terraformの主要な管理コマンド
- 今回は使用頻度の高いコマンドを記述します。
他にも使用するコマンドはありますが、追々別の記事で解説したいと
思います。

尚、管理コマンドを実行する際はTerraformのコードが記述されている
ファイル(`.tf`)のカレントディレクトリで行います。
&nbsp;

##### init
- terraformプロジェクトの初期化。
 Providerを追加,更新,削除した際には逐一実行する必要があります。
 具体的な挙動としては、コマンド実行後にカレントディレクトリに.terraformディレクトリが作成されます。
 この`.terraform`ディレクトリ以下には TerraformがProviderに対して操作を実行するためにプラグイン等の必要な情報が保持されます。

```zsh
terraform init
```

##### plan
- コードを適用(`apply`)する前に使用するコマンドです。
 印刷機で例えると、用紙を印刷する直前に画面上で実際のイメージを写してくれるようなイメージです。

```zsh
terraform plan
```

#### apply
- 実際にリソースをデプロイ又は変更します。
特に複数人で開発している際は、誤って他の人が作成したリソースに変更を加えないよう細心の注意を払う必要があります。

```zsh
terraform apply
```

#### destroy
- `apply`でデプロイしたリソースを削除します。
 サービスを停止してしまう可能性があるため、実行する際は細心の注意を払う必要があります。

```zsh
terraform destroy
```

#### fmt
- terraformのコードを記述するファイル(`.tf`)の記述を整形します。

```zsh
terraform fmt
```

#### refresh
- `output`や`variable`,`local`等の変数等の内容でステートファイルの内容を更新します。
実際のリソースの作成、削除、修正には関与しません。
```zsh
terraform refresh
```

- 以下コマンドだとrefreshを適用する前に一度内容を確認する事が出来るため、こちらが推奨されています。
```zsh
terraform apply -refresh-only
```

&nbsp;


## 4.CLI,HCLでAWS APIを呼び出せるよう認証情報の設定
- CLI及びプログラムでAWSアカウント内にアクセスするために認証情報を取得し、teraformをインストールした環境へ適用する必要があります。
今回は下記3つのパターンに分けて解説していきます。
尚、AWS CLIが既にインストールされている事を前提とします。

## IAMユーザー経由でのアクセス
##### ①検索:IAM > 「IAM」を押下
![](/images/terraform_install/iam_user1.png)

##### ②ユーザーの作成 > ユーザー名の入力 > 「次へ」を押下。
:::message
CLIでのアクセス専用ユーザーのため、マネジメントコンソールのアクセスは有効化しない。
:::
![](/images/terraform_install/iam_user2.png)
![](/images/terraform_install/iam_user3.png)
##### ③ポリシーを直接アタッチする > 要件に適した許可ポリシー >「次へ」を押下。
:::message
便宜上AdministratorAccessを付与していますが、許可ポリシーの内容はその組織の方針に応じて選択して下さい。
:::
![](/images/terraform_install/iam_user4.png)
##### ④入力内容の確認 > 「ユーザーの作成」を押下。
![](/images/terraform_install/iam_user5.png)

##### ⑤作成したIAMユーザーの「Access Key/Secret Access Key」を作成する。
#####   IAM > IAMユーザーの選択 > 「アクセスキーを作成」を押下。
![](/images/terraform_install/iam_user6.png)

##### ⑥コマンドラインインターフェイス(CLI)を選択 > 「次へ」を押下。
![](/images/terraform_install/iam_user7.png)

##### ⑦必要に応じて説明タグ値を入力 > 「アクセスキーを作成」 を押下。
![](/images/terraform_install/iam_user8.png)

##### ⑧認証情報の取得 > 「完了」を押下。
:::message
Copy or CSVファイルをダウンロードして認証情報を保管する。
:::
![](/images/terraform_install/iam_user9.png)
##### ⑨ターミナルのコマンド入力がAWSアカウントに認証されるよう設定
```zsh
aws configure --profile <IAMユーザー名/例:terraform>
AWS Access Key ID [None]:<IAMユーザーのaccess keyを入力>
AWS Secret Access Key [None]:<IAMユーザーのsecret access keyを入力>
Default region name [None]:<リソースを作成するデフォルトリージョンを入力/例:ap-northeast-1>
Default output format [None]:<コマンドの実行結果の出力形式 /例:json>
```
```none
<aws configureコマンドの留意事項>
※パラメータは対話形式で入力し、「~/.aws/credentials」,「~/.aws/config」に
 自動的に反映されます。
※認証情報の漏洩,誤用防止の観点で、--profileオプションを用いて設定する事が
 推奨されています。(オプションを用いない場合は、defaultとして設定)
```

##### ⑩ご自身の環境からCLI経由でAWSアカウントにアクセスが確認出来れば完了。
![](/images/terraform_install/iam_user10.png)
&nbsp;

## EC2インスタンス(Linux)でIAMロール経由のアクセス
##### ①IAM > ロールを作成 > AWSのサービス > EC2を選択 > 「次へ」を押下。
![](/images/terraform_install/role1.png)
![](/images/terraform_install/role2.png)
![](/images/terraform_install/role3.png)

##### ②要件に適した許可ポリシー(例:AdministratorAccess) > 「次へ」を押下。
![](/images/terraform_install/role4.png)

##### ③IAMロール名の設定 > 設定内容の確認 > 「ロールを作成」を押下。
![](/images/terraform_install/role5.png)
![](/images/terraform_install/role6.png)
![](/images/terraform_install/role7.png)

##### ④作成済みのEC2インスタンスへ作成したIAMロールを付与。
- 対象のEC2を選択 > アクション▲ > セキュリティ > IAMロールを変更 >
 IAMロールを選択 > 「IAMロールの更新」を押下。
 ![](/images/terraform_install/role8.png)
 ![](/images/terraform_install/role9.png)

##### ⑤EC2インスタンスへログインし、CLIでAWSアカウントにアクセス出来れば設定完了。
![](/images/terraform_install/role10.png)


&nbsp;
## `IAM Identity Center`/ `Organizations`でユーザ管理を行っている場合
- 複数のAWSアカウントを持つ組織の場合に用いられる管理方法です。
ユーザ管理を中央集権的に行う事で人為的なミスを回避してセキュリティの向上等が見込めます。
他にもOrganizationsで管理する事によるメリットもありますが、本記事では割愛します。

##### ①「Command line or programmatic access」を押下。
![](/images/terraform_install/sso1.png)

##### ②ポップアップで一時的な認証情報が表示されるため、環境変数として設定する。
![](/images/terraform_install/sso2.png)

##### ③ ご自身のローカル環境又はEC2等のLinux環境からCLI経由でAWSアカウントにアクセスが出来る事を確認出来れば設定完了。
![](/images/terraform_install/sso3.png)

## 完