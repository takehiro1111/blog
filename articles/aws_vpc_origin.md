---
title: "Amazon CloudFront VPC オリジンをTerraformで設定"
emoji: "📝"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Terraform","AWS"]
published: false
---

## VPCオリジンとは？
- **AWS re:Invent 2024**で新発表された機能です。  
例えば、ALBを用いた従来の構成だとALBをパブリックサブネットに配置してCloudFrontのマネージドプレフィクスで  
CloudFront経由のアクセスに制限していましたが、VPCオリジンの設定によってALBをプライベートサブネットに配置でき、よりシンプルな設定でセキュアな環境を作れるようになります。
また、ALBをパブリックサブネットに配置することでパブリックIPの料金がかかっていましたが、これを削減する副次効果もあります。

- [AWS公式ブログ](https://aws.amazon.com/jp/blogs/news/introducing-amazon-cloudfront-vpc-origins-enhanced-security-and-streamlined-operations-for-your-applications/)での記載
> Amazon Virtual Private Cloud (Amazon VPC) 内のプライベートサブネットでホストされているアプリケーションからのコンテンツ配信を可能にする新機能です。

### 従来の構成
構成図
### VPCオリジンを用いた構成
構成図

### 既存構成の修正点
- CloudFront
  - VPCオリジンの作成
    - VPCオリジン用のENIが作成され、自動的に専用のセキュリティグループも作成されます。
      - セキュリティグループのインバウンドルールは穴あけしなくて良い。
  - CloudFrontディストリビューションのオリジン設定でVPCオリジンを有効化。
- ALB
  - ALBのセキュリティグループでVPCオリジンのENIにアタッチされているSGをインバウンドルールで許可。
  - ALBをInternal用で再作成する。
  - プライベートサブネットに配置する

## TerraformでのVPCオリジンの実装
- ALBやCloudFrontの設定変更などは既に様々なテックブログで発信されているため割愛し、    
本記事ではVPCオリジンをコードで設定することに焦点を当てて記載します。

### Resourceブロックでの設定
- [Reference](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_vpc_origin)
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
  ### 省略 ###
  origin {
    connection_attempts = 3
    connection_timeout  = 10
    domain_name         = {ALBのDNS名}
    origin_id           = {オリジンサーバの識別子}

    vpc_origin_config {
      vpc_origin_id            = aws_cloudfront_vpc_origin.this.id
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
    }
  }
  ### 省略 ###
}

```

### 公式Moduleでの設定
:::alert
バージョン4.0.0からの対応になるため、実装する際に必ず確認してください。
:::
https://registry.terraform.io/modules/terraform-aws-modules/cloudfront/aws/latest

[Reference](https://github.com/terraform-aws-modules/terraform-aws-cloudfront)
```hcl
module "cloudfront_vpc_origin_test" {
  source  = "terraform-aws-modules/cloudfront/aws"
  version = "4.0.0"

  ### 省略 ###
  create_vpc_origin = true
  vpc_origin = {
    name                   = "test"
    arn                    = {ALBのARN}
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "https-only"

    origin_ssl_protocols = {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  origin = {
    origin_alb = {
      domain_name = {ALBのDNS名}
      origin_id   = {オリジンサーバの識別子}

      vpc_origin_config = {
        vpc_origin_id            = module.cloudfront_vpc_origin_test.cloudfront_vpc_origin_ids
        origin_keepalive_timeout = 5
        origin_read_timeout      = 30
      }
    }
  }
  ### 省略 ###
}

```
## 出来上がりのWebページの画面

## まとめ
今回の記事では、以下を実装しました：

- VPCオリジンをTerraformを用いた実装

VPCオリジンをTerraformで実装する場合はご参考になれば嬉しいです！
