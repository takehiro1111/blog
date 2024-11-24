---
title: "Terragruntを用いてTerraformのディレクトリ構成を変更した話"
emoji: "🕌"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Terraform","Terragrunt","AWS"]
published: false
---

![](/images/tf_tg/tf_tg.jpeg =400x)

## 1.背景
- 弊社では、各AWSアカウントごとにディレクトリを切り、`production`,`acc`,`staging`の環境ごとに
　サブディレクトリを切ってtfstateを分けています。(前提として、単一のAWSアカウントの中に複数環境が混在します。)
   私が入社してから既に出来上がっていた構成のため理由は分からないのですが、サービス自体の規模が大きくない事並びに
   outputの管理工数を割くリソースが無いため、あまり細かくtfstateを切るような事をしてないのかと思います。
  ```zsh:ディレクトリ構成イメージ
  tree -d -L 2
.
├── account_A
│   ├── acc
│   ├── production
│   └── staging
├── account_B
│   ├── acc
│   ├── production
│   └── staging
├── account_C
│   ├── acc
│   ├── production
│   └── staging
  ```

- 上記のような状況があり、個人のリポジトリではもっと色々と試してみたいと感じるようになりました。
また、terraformのラッパーツールである`terragrunt`も組み込んでみたかったため、以下のようにしました。
大分省略していますが、イメージとしては技術的なレイヤーで区切ってterragruntでstateファイルを中央制御しています。
```zsh:takehiro1111/aws_terraform/developemnt/
.
├── development
│   ├── compute
│   │   ├── xx.tf
│   │   └── terragrunt.hcl
│   ├── database
│   │   ├── xx.tf
│   │   └── terragrunt.hcl
│   ├── management
│   │   ├── xx.tf
│   │   └── terragrunt.hcl
│   ├── network
│   │   ├── xx.tf
│   │   ├── terragrunt.hcl
│   ├── security
│   │   ├── xx.tf
│   │   ├── terragrunt.hcl
│   ├── storage
│   │   ├── xx.tf
│   │   └── terragrunt.hcl
│   └── terragrunt.hcl
│   ├── locals.yml
```

## 3.ディレクトリ構成のメリット・デメリット


## 2.terragruntとは?


## 4.terragruntのコード

