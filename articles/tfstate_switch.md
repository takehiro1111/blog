---
title: "ステートファイルの切り替えコマンド"
emoji: "🎉"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Terraform","aws","IaC","SRE","インフラエンジニア"]
published: false
---

## backend設定の切り替え

- backendを別設定へ切り替える際は、コードの記述を変更して以下コマンドを実行します。
例えば、Terraformで構築し始めの際にストレージを用意出来ていない場合に一時的にlocalに設定した後にS3に変更するケースで用います。
切り替え前のファイルが不要な場合は、コマンド実行後に削除します。


#### 切り替え前のファイルから切り替え後のファイルに既存内容をコピーする必要がある場合

```
terraform init -migrate-state
```

#### 切り替え前のファイルから切り替え後のファイルに既存内容をコピーしない場合
```
terraform init -reconfigure
```

- 例1）local→S3に変更する場合
```
backend "local" {
  path = "tfstate/terraform-state" 
}
```

↓　　↓　　↓

```
backend "s3" {
    bucket  = "backend-common"
    key     = "main"
    region  = "ap-northeast-1"
    acl     = "private"
    encrypt = true
  }
```
:::message
コマンドを実行しないと以下エラーになる。
:::
![](/images/tfstate_switch/init_fail.png)

- localで保管しているステートファイルの中身をs3へコピーしてbackend設定を移行してsuccessfullyが表示されれば設定完了。
```
terraform init -migrate-state
```
![](images/tfstate_switch/init_migrate_state.png)

&nbsp;
- 例2）S3からlocalに戻す場合(ステートファイルに差異がなく直後に切り戻す場合)

```
backend "s3" {
    bucket  = "backend-common"
    key     = "main"
    region  = "ap-northeast-1"
    acl     = "private"
    encrypt = true
  }
```
↓　　↓　　↓
```
backend "local" {
  path = "tfstate/terraform-state" 
}
```
```
terraform init -reconfigure
```
![](images/tfstate_switch/init_reconfigure.png)