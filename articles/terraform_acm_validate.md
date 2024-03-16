---
title: "[Terraform/AWS]ACM作成、ドメイン検証"
emoji: "💬"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: []
published: false
---
![](/images/terraform_logo.png)

## 本記事を読み終わった時のゴール
- コードベースでACM作成並びにドメイン検証の仕組みを理解できる事

## 前提
- 東京リージョンに作成し、ALBにアタッチすることを想定しています。
- ドメイン検証のパラメータ説明に焦点を当てており、ホストゾーン等周辺の環境は記載していません。
- 簡易的に記載しているため、ハードコードでドメインを定義しています。

&nbsp;

## ACMの作成

```hcl:./main.tf
// ACMを作成。
resource "aws_acm_certificate" "example" {
  domain_name               = "*.example.com"
  validation_method         = "DNS" // ここでDNS検証を行うことを設定している
  subject_alternative_names = [example.com]

  lifecycle {
    create_before_destroy = true
  }
}

// ドメイン検証のレコード設定
resource "aws_route53_record" "example" {
  for_each = {
    for dvo in aws_acm_certificate.example.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true // 既存のレコードがある場合は上書きする
  name            = each.value.name 
  records         = [each.value.record]
  type            = each.value.type
  ttl             = 60
  zone_id         = aws_route53_zone.example.zone_id
}

// ドメイン検証の実施
resource "aws_acm_certificate_validation" "example" {
  certificate_arn         = aws_acm_certificate.example.arn
  validation_record_fqdns = [for record in aws_route53_record.example : record.fqdn]
}
// 
```