---
title: "TerraformをRenovateで自動バージョン管理し、PRとマージを完全自動化する"
emoji: "🐡"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Renovate","Terraform"]
published: true
---

![](/images/renovate/renovate_logo.png)

## Renovateとは？
- ドキュメントで`Automated dependency updates. Multi-platform and multi-language.`と記載されています。
簡潔に言うと依存関係を自動で更新してくれるツールです。
バージョンアップしてくれ、PR作成~Mergeまで自動で行ってくれます。
:::message
reference:https://docs.renovatebot.com/
:::

# Dependabotとの比較
### Renovateを採用するメリット
  - Renovateだと異なる種類の依存関係でも、プロジェクト単位で1つのPRにまとめてくれてPRの数が少なくなり管理が容易になる。
    - Dependabotだと同じ種類の依存関係でもPRが分離されPR数が多くなってしまい管理がしにくい。
  - 特定のパッケージやモジュールのみを更新対象にしたり、週に一度だけPRを作成するように設定できる等カスタマイズしやすい。
    - Dependabotは、設定できるパラメータが限られており、Renovateほどの自由度がない。
  - テストやレビューが不要な場合、PRの作成からマージまでを完全に自動化できる。(DependabotだとCIをセットにしないとMergeまでやってくれない)
    - Dependabotは、更新後のコードがプロジェクトで正常に動作することを確認するためにCIでテストを実行する必要があるため。

# 前提
- RenovateとGithubが連携済みであること
https://github.com/apps/renovate
![](/images/renovate/alignment_github_full.png)

:::message
reference:https://qiita.com/ksh-fthr/items/40732b6396f36c62bea2
:::


# `renovate.json`の配置
- 基本的にはリポジトリの`ルートディレクトリ` or `.github`配下に配置します。  
ルートディレクトリが最優先されるので、特別に理由がない場合はルートディレクトリに配置します。
![](/images/renovate/doc_dir.png)

# コードとパラメータの解説
- バージョンアップしたい対象
  - terraformブロック
  - `.terraform-verison`ファイル
  - providerブロック
  - 公式Module

- スコープ
  - Terraformのバージョン更新を自動で管理し、PR作成からMergeまでを自動化
  - 個人用のリポジトリのため、更新優先のためメジャーバージョンも対象

```json:takehiro1111/aws_terraform/renovate.json
// reference: https://docs.renovatebot.com/configuration-options/#additionalbranchprefix
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:best-practices",
    ":label(renovate)",
    ":timezone(Asia/Tokyo)"
  ],
  "configMigration": true,
  "prHourlyLimit": 0,
  "prConcurrentLimit": 0,
  "schedule": [
    "* 8-23,0-2 * * *"
  ],
  "assignAutomerge": true,
  "assignees": [
    "takehiro1111"
  ],
  "autoApprove": true,
  "automerge":true,
  "automergeType":"pr",
  "automergeStrategy":"auto",
  "rebaseWhen": "conflicted",
  "dependencyDashboard": true,
  "packageRules": [
    {
      "matchManagers": ["terraform", "terraform-version", "tflint-plugin"],
      "additionalBranchPrefix": "{{packageFileDir}}-",
      "commitMessageSuffix": "({{packageFileDir}})",
      "matchUpdateTypes": ["major", "minor", "patch"],
      "groupName": "terraform"
    }
  ]
}
```

### 上記コードの結果、バージョン更新を行いPR作成〜Mergeまで自動化される。
![](/images/renovate/pr_merge_by_renovate.png)
![](/images/renovate/pr_merge_by_renovate_files.png)

## 参考
https://docs.renovatebot.com/configuration-options/
https://qiita.com/ksh-fthr/items/40732b6396f36c62bea2
https://inside.dmm.com/articles/renovate-dependency-management-automation/
https://www.blogaomu.com/entry/try-renovate-auto-merge
https://zenn.dev/book000/articles/renovate-dep-auto-update