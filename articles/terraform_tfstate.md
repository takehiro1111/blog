---
title: "ステートファイルの管理方法,切り替え"
emoji: "🕌"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: []
published: false
---

![](/images/terraform_logo.png)

## 本記事を読み終わった時のゴール
- ステートファイルの概念、必要性を認識出来る事。
- 状況に応じて適切なbackendの設定が出来る事。
&nbsp;

## 目次
1. ステートファイルの概要
2. ステートファイルの構文,ロック機能の記述
3. backend設定のパターン別解説
4. backend設定の切り替え(例:local⇔S3)
&nbsp;

## 本編
1. ステートファイルの説明

- ステートファイルとは？
    Terraform管理下で実際に構築されているリソースのマッピング情報がJSONフォーマットで記述されるファイル。
    Terraformが内部的に使用するプライベートなAPIである。

- 何故、必要なのか？
結論としては、Terraformが管理するリソース情報をTerraform自身に識別させるため。

例えば、以下EC2インスタンスのリソースを管理する場合、TerraformはAWSアカウントに実際に存在するインスタンスのID,name,設定値と対応している事をこのJSONフォーマットを通して認識して管理する。
ちなみに、`terraform plan`はこのステートファイルとの差分を検知してリソースの作成,修正,削除等の情報を表示する。
ステートファイルと実際の設定に差異が見られない場合は、
`No Changens.` と表示される。

### Terraformで構築するリソース

```hcl:stateファイルの元になるEC2インスタンス
resource "aws_instance" "test_blog" {
  ami = "ami-0dafcef159a1fc745"
  instance_type = "t2.micro"
}
```

```none:上記で作成したEC2インスタンスのステートファイルの中身
"resources": [
    {
      "mode": "managed",
      "type": "aws_instance",
      "name": "test_blog",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "schema_version": 1,
          "attributes": {
            "ami": "ami-0dafcef159a1fc745",
            "arn": "arn:aws:ec2:ap-northeast-1:{アカウントID}:instance/i-{インスタンスID}",
            "associate_public_ip_address": true,
            "availability_zone": "ap-northeast-1a",
      以下、省略
```
&nbsp;

2. ステートファイルを設定する構文,ロックの説明
- ステートファイルを設定する構文
    基本的には、以下のようにterraformブロックの中に設定を記述する。
    プロジェクトの要件に応じてステートファイルの保管形式を設定する必要がある。
    NBではS3に保管している為、例としてS3に保管する設定を以下へ記載する。

```none:ステートファイルの保管先
・ローカル環境→local
・AWS→S3 
・GCP→Cloud Storage 
・Azure→Azure Blob Storage 
・Terraform Cloud/Enterprise→remote
```

- リモートバックエンドをS3に設定する例

```hcl:config.tf
terraform {
  required_version = "1.6.4"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.26.0"
    }
  }

  backend "s3" {
    bucket  = "terraform-state"
    key     = "test"
    region  = "ap-northeast-1"
    acl     = "private"
    encrypt = true
    dynamodb_table = "tfstate-locks" 
  }
}
```


- ステートファイルのロック機能

    複数人でterraformを扱う際にメンバー同士で同じバージョンのステートファイルに同じタイミングでapplyしないためにロック機能の設定が推奨されます。
    Terrformではネイティブでロック機能をサポートしていますが、DynamoDBでもロック機能を実装出来ます。
    DynamoDBはAWSのNoSQLのDBで、強力な整合性のある読み込みと条件付き書き込みという分散ロックシステムに必要な機能をサポートしています。（コストもほぼ無料でインフラ面での運用工数もかかりません。）

    - 強力な整合性
        データが更新された直後にそのデータを読み込むと、最新の状態が反映されていることを保証する機能。

    - 条件付き書き込み
        特定の条件下にある場合のみDBに書き込みを許可する機能。
        ロック状態が既に存在する場合にのみ書き込みを許可し競合を防ぐ。

```database.tf
resource "aws_dynamodb_table" "tfstate_lock" {
    name = "tfstate-lock-table"
    billing_mode = "PAY_PER_REQUEST"
    hash_key = "LockID"

    attribute {
    name = "LockID"
    type = "S"
    }   
}
```
```hcl:config.tf
// ステートファイルのリモートバックエンドの設定のみ抜粋
backend "s3" {
    bucket  = "backend-common"
    key     = "test"
    region  = "ap-northeast-1"
    acl     = "private"
    encrypt = true
    dynamodb_table = "tfstate-lock-table" 
  }
```

- DynamoDBテーブルのLockIDの実際の設定
画像の例では、ステートファイルの名称が`backend-common`に対して、DynamoDBの`tfstate-lock-tabl`でロック機能を制御しています。
![](/images/terraform_tfstate/lock_dynamodb.png)

&nbsp;


3. backend設定のパターン別解説
    以下3つのパターンに分けて記述する。


### ローカル環境で管理する方法
主に個人開発や自己学習で簡易的な環境を作成する際またはストレージが作成されるまでの一時的な用途で設定。

```config.tf
backend "local" {
    path = "tfstate/terraform-state" 
} 
```

### クラウドサービスのストレージで管理する方法
ステートファイルに複数人でアクセスするする必要がある場合の設定。

- 同一ファイルで定義する場合
```hcl:config.tf
terraform {
  required_version = "1.6.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.26.0"
    }
  }

  backend "s3" {
    bucket  = "backend-common"
    key     = "main"
    region  = "ap-northeast-1"
    acl     = "private"
    encrypt = true
  }
}
```

:::note warn
S3バケットをbackendに設定する場合、以下のようにバケットポリシーを設定してTerraformがS3バケットに対する操作を可能にする必要がある。
:::

```json:s3バケットポリシー
  {
   "Version": "2012–10–17",
     "Statement": [
     {
       "Sid": "RootAccess",
       "Effect": "Allow",
       "Principal": {
       "AWS": "arn:aws:iam::{AWSアカウントID}:root" // 例として、AWSアカウントのrootユーザーへの許可している。
        },
       "Action": "s3:*",
       "Resource": [
         "arn:aws:s3:::backend-common",
         "arn:aws:s3:::backend-common/*"
        ]
      }
    ]
  }
```


- 共通設定を外出しする場合
    環境毎にbackend設定のパラメータをコピペするのは面倒に感じると思います。
    その場合、以下のように共通設定は別ファイル(.hcl)に切り出し、terraform init -backend-config={パス/切り出したファイル名}で個別のモジュールから設定ファイルを指定する事が可能です。

```hcl:./backend.hcl
// backendの共通設定を外出しする事で各モジュールで指定しなくて良い。
bucket  = "backend-common"
region  = "ap-northeast-1"
acl     = "private"
encrypt = true
```

```hcl:./config.tf
terraform {
  required_version = "1.6.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.26.0"
    }
  }

  backend "s3" {
    key     = "main" //key以外の共通情報は外出ししているためここでは記載不要。
  }
}
```

```hcl:./stg/config.tf
terraform {
  required_version = "1.6.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.26.0"
    }
  }
  
  backend "s3" {
    key     = "stg"
  }
}
```

```hcl:./prod/config.tf
terraform {
  required_version = "1.6.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.26.0"
    }
  }
  
  backend "s3" {
    key     = "prod"
  }
}
```

- 親モジュールのカレントディレクトリに存在する`.hcl`ファイルをパス指定する場合のコマンドを入力して読み込む。
```コマンド
terraform init -backend-config=../backend.hcl
```
![](/images/terraform_tfstate/init_-backend-config.png)


- terragruntで管理する方法
 Terraform のラッパーで設定を簡素化し、コードの重複を減らす事が可能になる。

#### メリット
- DRY原則の実施
複数の環境（stg,acc,prod等）で共通の Terraform 設定（本記事ではバックエンド設定）を一箇所で管理し、再利用出来る。
- 環境の分離
環境ごとに異なるディレクトリ構造を使用し、固有のステートファイルを保持することが出来る。
- 全てのモジュールに対して一括操作が可能。(個別のterraformコマンドの操作も可能。)
メインdirから以下コマンドを実行し、サブディレクトリに存在するモジュールを更新できる。
`terragrunt run-all {init/plan/apply/destroy等}`
- リモートバックエンドの自動作成


#### デメリット
- 環境を分けずに単一のディレクトリ配下でリソースを管理する場合には向かない。

以下のディレクトリ構成でメインディレクトリ内でterragruntコマンドを実行。



```hcl:./config.tf
terraform {
  required_version = "1.6.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.26.0"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region  = "ap-northeast-1"
  profile = "{任意の認証ユーザ名}"
}
```

```hcl:./terragrunt.hcl
remote_state {
    backend = "s3"
    
    config = {
    bucket  = "{任意のバケット名}"
    key     = "${path_relative_to_include()}.tfstate"
    region  = "ap-northeast-1"
    acl     = "private"
    encrypt = true
    }
}
```
&nbsp;

```hcl:./project/dev/terragrunt.hcl
// メインディレクトリで設定しているステートファイルに向けている。
include {
  path = find_in_parent_folders()
}
```

```hcl:./project/dev/config.tf
terraform {
  required_version = "1.6.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.26.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region  = "ap-northeast-1"
  profile = "{任意の認証ユーザ名}"
}
```

```hcl:./project/dev/ec2.tf
resource "aws_instance" "test" {
  ami = "ami-0dafcef159a1fc745"
  instance_type = "t2.micro"
}
```


## 参考
- 詳解 Terraform 第3版 
 https://www.oreilly.co.jp/books/9784814400522/