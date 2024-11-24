---
title: "[S3 Intelligent-Tiering]概要とTerraformでの実装"
emoji: "📌"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["AWS","S3","Terraform"]
published: true
---
## 0.本記事を書いている経緯
- 業務でS3周りのコスト削減の一環として**S3 Intelligent-Tierring**の設定を行う予定だが、その前段階で導入に必要なコストや懸念点を調査している。  
その過程で自身の備忘録として残しています。

## 1.概要([参照](https://docs.aws.amazon.com/ja_jp/AmazonS3/latest/userguide/intelligent-tiering.html))
### 1-1.設定する目的
  - S3に関連するコスト削減を行いたいため。どのオブジェクトがどの程度使用されるか判断がつかない状態で、安易にライフサイクルポリシーでGracierへ移行したり出来ないため、AWS側でアクセスパターンを検知し、オブジェクトを最適な階層へ移行してくれる。
### 1-2.機能
  - Amazon S3 のストレージクラスで、アクセスパターンに基づいてデータを自動的に移動することでストレージコストを最適化する機能。
  - 各階層に移行後オブジェクトがアクセスされると、そのオブジェクトは S3 Intelligent-Tiering によって自動的に高頻度のアクセス階層に戻される。

### 1-3.Intelligent-Tieringへの移行期間
  - 最短0日から設定可能

### 1-4.アクセス階層([参照](https://docs.aws.amazon.com/ja_jp/AmazonS3/latest/userguide/intelligent-tiering-overview.html))

| 期間(各階層に移行されてから最後にアクセスされた日) | 移行先 | 標準取得時間 |
| --- | --- | --- |
| デフォルト | 高頻度アクセス階層 | 低レイテンシー(ミリ秒単位) |
| +30日間連続アクセスなし | *低頻度アクセス階層*  | 低レイテンシー(ミリ秒単位) |
| +90 日間連続アクセスなし | アーカイブインスタントアクセス層 | 低レイテンシー(ミリ秒単位) |
| +90 日間連続アクセスなし | アーカイブアクセス階層 | 3～5h |
| +180 日間連続アクセスなし | ディープアーカイブアクセス階層 | 12 h以内 |

:::message
- アーカイブアクセス階層とディープアーカイブアクセス階層は非アクセス日程(オブジェクトが最後にアクセスされた日から経過した日数)のカスタマイズ可能。（90〜730日）
- 低頻度アクセス階層から、直接アーカイブアクセス層やディープアーカイブアクセス層に移行することが可能。（180〜730日）
- 移行自体は、AWS側に責任があるためユーザーでは制御できない。
:::
&nbsp;

## 2.コスト([参照](https://aws.amazon.com/jp/s3/pricing/))
- 監視・オートメーション料金 
:::message alert
- **S3 Intelligent-Tiering は、オートティアリングで対象となるオブジェクトの最小サイズが `128 KB` となっている。** 
- **128KB未満のオブジェクトはモニタリングされず、常に高頻度アクセスティア料金で課金され、モニタリング料金やオートメーション料金は発生しない。**
:::

| 料金(USD) |
| --- |
| **0.0025(オブジェクト 1,000 件あたり )** |

- ストレージ料金

| 階層 | 料金(USD)/月 |
| --- | --- |
| 高頻度アクセス階層（S3 スタンダード相当） | **0.023/GB(最初の50TB)** / **0.022/GB(次の450TB)** / **0.0021/GB(500TB超)** |
| 低頻度アクセス階層（S3 標準 - 低頻度アクセス相当） | **0.0125/GB** |
| アーカイブインスタントアクセス階層() | **0.004/GB** |
| アーカイブアクセス階層() | **0.0036/GB** |
| ディープアーカイブアクセス階層（S3 Glacier Deep Archive 相当） | **0.00099/GB** |



&nbsp;
## 3.導入にあたって気にしたい点
### 3-1.対象のファイルサイズ
- ファイルのサイズが**128KB未満**だとアクセスパターンのモニタリング対象に入らず、高頻度階層のストレージに残る。
  - 自身のバケットのオブジェクトサイズを予め把握しておかないと、導入しても意味がなくなるため。

### 3-2.Archive階層の取り出し時間
| アクセス階層 | オブジェクト取得時間 |
| --- | --- |
| アーカイブインスタントアクセス階層 | 低レイテンシー(ミリ秒単位) |
| アーカイブアクセス階層 | 3～5h |
| ディープアーカイブアクセス階層 | 12 h以内 |

### 3-3.移行パス([参照](https://docs.aws.amazon.com/ja_jp/AmazonS3/latest/userguide/lifecycle-transition-general-considerations.html#lifecycle-general-considerations-transition-sc))
  - 既に`One Zone-IA`や`Glacier`のバケットからは`Intelligent-tiering`へ移行できない。
  ![](/images/s3_tier/life_cycle_pass.png)

&nbsp;
## 4.Terraformでの実装
### 4-1.Resourceブロック
:::message
- 特定のオブジェクトにフィルターしておらず、バケットの中の全てのオブジェクトに反映される内容になっています。
:::
```hcl
// ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration
resource "aws_s3_bucket_lifecycle_configuration" "example" {
  bucket = {バケット名}

  rule {
    id = "Allow small object transitions in INTELLIGENT_TIERING"
    status = "Enabled"

    filter {
      object_size_greater_than = 131072 # /バイト単位 / (128KB)  128KB未満のオブジェクトはアクセス頻度の確認が対象外のため。
    }
    noncurrent_version_expiration {
      newer_noncurrent_versions = 3 // 非現行バージョンを3世代保持。それ以前の古いバージョンは削除される。
      noncurrent_days = 30 // オブジェクトが非現行バージョンになってから、アクション（削除や移行）が実行されるまでの日数
    }
    transition {
      days          = 0 // オブジェクトが格納されて24h以内にIntelligent-Tireringへ移行
      storage_class = "INTELLIGENT_TIERING"
    }
  }
}

// ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_intelligent_tiering_configuration
resource "aws_s3_bucket_intelligent_tiering_configuration" "example" {
  bucket = {バケット名}
  name   = "Intelligent-Tirering-Archive-Option"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }
  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
}
```

### 4-2.AWS公式Module
```hcl
// ref: https://github.com/terraform-aws-modules/terraform-aws-s3-bucket/blob/master/main.tf
  # aws_s3_bucket_lifecycle_configuration
  lifecycle_rule = [
    {
      id = "intelligent-tireling"
      status = "Enabled"
      filter = {
        object_size_greater_than = 131072
      }
      noncurrent_version_expiration = {
        newer_noncurrent_versions = 3
        noncurrent_days           = 30
      }
      transition = {
        days          = 0 
        storage_class = "INTELLIGENT_TIERING"
      }
    }
  ]
  
  # aws_s3_bucket_intelligent_tiering_configuration
  intelligent_tiering = [ 
    {
      status = true
      tiering = {
        ARCHIVE_ACCESS = {
          days = 90
        }
        DEEP_ARCHIVE_ACCESS = {
          days = 180
        }
      }
    }
  ]
```



## 参考

https://docs.aws.amazon.com/ja_jp/AmazonS3/latest/userguide/intelligent-tiering-overview.html

https://aws.amazon.com/jp/s3/storage-classes/intelligent-tiering/#:~:text=S3%20Intelligent%2DTiering%20%E3%81%AF%E3%80%81%E3%83%87%E3%83%BC%E3%82%BF,%E3%81%AE%E3%82%AF%E3%83%A9%E3%82%A6%E3%83%89%E3%82%B9%E3%83%88%E3%83%AC%E3%83%BC%E3%82%B8%E3%82%AF%E3%83%A9%E3%82%B9%E3%81%A7%E3%81%99%E3%80%82
https://aws.amazon.com/jp/s3/pricing/

https://aws.amazon.com/jp/getting-started/hands-on/getting-started-using-amazon-s3-intelligent-tiering/
https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration

https://docs.aws.amazon.com/ja_jp/AmazonS3/latest/userguide/lifecycle-transition-general-considerations.html#lifecycle-general-considerations-transition-sc

https://www.slideshare.net/slideshow/20190220-aws-black-belt-online-seminar-amazon-s3-glacier/133346950#45

https://zenn.dev/chonan_kai/articles/28911c85e05cfc
https://dev.classmethod.jp/articles/amazon-s3-intelligent-tiering-further-automating-cost-savings-for-short-lived-and-small-objects/

https://blog.serverworks.co.jp/s3-intelligent-tiering-set

https://techblog.locoguide.co.jp/entry/2023/05/15/153931


