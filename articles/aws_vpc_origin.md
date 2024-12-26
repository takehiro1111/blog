---
title: "CloudFrontの新機能『VPCオリジン』をTerraformで書いてみた"
emoji: "📝"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Terraform","AWS"]
publication_name: "nextbeat"
published: false
---
![](/images/terraform_logo.png)

## 1.VPCオリジンとは？
- [AWS公式ブログ](https://aws.amazon.com/jp/blogs/news/introducing-amazon-cloudfront-vpc-origins-enhanced-security-and-streamlined-operations-for-your-applications/)での記載
> Amazon Virtual Private Cloud (Amazon VPC) 内のプライベートサブネットでホストされているアプリケーションからのコンテンツ配信を可能にする新機能です。

**AWS re:Invent 2024**で新発表された機能です。  
プライベートサブネット内のアプリケーションを直接CloudFrontを通じて配信可能なため、よりセキュアな構成を実現できる機能です。

### 従来の構成イメージ
![](/images/vpc_origin/ecs_conventional.png  =500x)

### VPCオリジンを用いた構成イメージ
![](/images/vpc_origin/ecs_conventional2.png  =500x)

## 2.メリット
### ①セキュリティの強化
- ALBをパブリックサブネットに配置する必要がなくなるため、外部からの直接アクセスを防げて、より簡潔な設定でCloudFront経由のアクセスに絞れる。

### ②コスト削減
- グローバルIPアドレスの必要性がなくなることで、そのコストを削減できる。  
ALBは各AZにノードを配置するため、AZ数に応じて以下のコストが削減可能となる。

#### Reference
https://aws.amazon.com/jp/blogs/news/new-aws-public-ipv4-address-charge-public-ip-insights/

```txt:コスト計算
### 単一のパブリックIPの月額コスト
$0.005 * 24h * 30日 = $3.6/月

### 2つのAZ(最小構成)でALBを設定している場合
$3.6 * 2 = $7.2/月

## 3つのAZでALBを設定している場合
$3.6 * 3 = $10.8/月
```

## 3.デメリット
### ①Terraformで構築する際の依存関係
- リソースを作成する際は問題なかったが、修正する際には一度CloudFrontでVPCオリジンの設定を無効化してからでないとVPCオリジンの設定を変更できなかったので少し面倒。

### ②ENI作成の制限
- 大規模な開発環境だと、ENIの作成が[VPCクォータ](https://docs.aws.amazon.com/ja_jp/vpc/latest/userguide/amazon-vpc-limits.html#vpc-limits-enis)に引っ掛かる可能性がある。

## 4.従来構成からの修正点
- **CloudFront**
  - VPCオリジンの作成
    - VPCオリジンのENIが作成され、自動的に専用のセキュリティグループも作成される。
  - CloudFrontディストリビューションのOrigin設定でVPCオリジンを有効化。
- **ALB**
  - ALBのセキュリティグループでVPCオリジンのENIにアタッチされているSGをインバウンドルールで許可。
  - ALBをInternal用で再作成する。（本番環境での切り替えはブルーグリーンなど検討）
  - プライベートサブネットに配置。

## 5.TerraformでのVPCオリジンの実装
- ALBやCloudFrontの設定変更などは既に様々なテックブログで発信されているため割愛し、    
本記事ではVPCオリジンをコードで設定することに焦点を当てて記載します。

### ①Resourceブロックでの定義
https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_vpc_origin
```hcl
resource "aws_cloudfront_vpc_origin" "this" {
  vpc_origin_endpoint_config {
    name                   = "test"
    arn                    = {ALBのARN}
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "https-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  ### 抜粋 ###
  origin {
    connection_attempts = 3
    connection_timeout  = 10
    domain_name         = {ALBのDNS名}
    origin_id           = {オリジンサーバの識別子}

    vpc_origin_config {
      vpc_origin_id            = aws_cloudfront_vpc_origin.this.id
      origin_keepalive_timeout = 5 // CloudFront がオリジンへの接続を維持する秒数
      origin_read_timeout      = 30 // CloudFront がオリジンからの応答を待機する秒数
    }
  }
  ### 抜粋 ###
}

```

&nbsp;
### ②AWSプロバイダが提供しているModuleでの定義
https://registry.terraform.io/modules/terraform-aws-modules/cloudfront/aws/latest

https://github.com/terraform-aws-modules/terraform-aws-cloudfront
:::message alert
Ver`4.0.0`からの対応になるため、実装する際に必ず確認してください。
:::

```hcl
module "cloudfront_vpc_origin_test" {
  source  = "terraform-aws-modules/cloudfront/aws"
  version = "4.0.0"

  ### 抜粋 ###
  create_vpc_origin = true
  vpc_origin = {
    test_vpc_origin = {
      name = "test-vpc-origin"
      arn = module.alb_wildcard_takehiro1111_com.arn
      http_port = 80
      https_port = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols = {
        items = ["TLSv1.2"]
        quantity = 1
      }
    }
  }

  origin = {
    origin_alb = {
      domain_name = {ALBのDNS名}
      origin_id   = {オリジンサーバの識別子}

      vpc_origin_config = {
        vpc_origin_id            = module.cloudfront_vpc_origin_test.cloudfront_vpc_origin_ids[0]
        origin_keepalive_timeout = 5
        origin_read_timeout      = 30
      }
    }
  }
  ### 抜粋 ###
}

```

## 6.リクエスト確認
- VPCオリジン設定後にプライベートサブネットに配置したInternalALB経由でECSのテストページへアクセスし、`200`が返ることが確認出来ました。
![](/images/vpc_origin/cdn.png)


## 7.まとめ
今回の記事では、以下を記載しました。

- Terraformを用いたVPCオリジンの実装

TerraformでVPCオリジンを簡単に導入する方法を知る一助になれば幸いです！
