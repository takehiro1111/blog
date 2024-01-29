---
title: "Terraformのメタ引数"
emoji: "📚"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Terraform","aws","IaC","SRE","インフラエンジニア"]
published: false
---
![](/images/terraform_logo.png)

# 概要
- Terraformで使用する様々なメタ引数の解説
&nbsp;


# 本記事を読み終わった時のゴール
- 各メタ引数の構造や使い方を理解している状態
&nbsp;

# 目次


# 本編

:::message
前提:Terraformのインストールやプロバイダとの基本的な設定が完了している状態である事。
:::

## Count
### ループ
- 単純なループ
```hcl:main.tf
variable "test" {
  type    = list(string)
  default = ["test_a", "test_b", "test_c"]
}

resource "aws_iam_user" "test" {
  count = 2
  name  = "test-${count.index}"
}

```
- ビルトイン関数を使用した例
```hcl:main.tf
resource "aws_iam_user" "test_1" {
  count = length(var.test) //length関数で配列の要素数を返す = 3
  name  = var.test[count.index]
  path  = "/system/"
}

output "iam_user_name_all" {
  value = aws_iam_user.test_1[*].name // スプレット形式で配列の全ての要素を取ってくる。
}
```

- moduleを活用したケース
```hcl:./modules/iam/iam.tf
variable "module_user" {
  type    = string
  default = ""
}

resource "aws_iam_user" "test_module1" {
  name = var.module_user
  path = "/"
}

output "aws_iam_user" {
  value = aws_iam_user.test_module1.arn
}

```

```hcl:main.tf
variable "module_name" {
  type    = list(string)
  default = ["module_user1", "module_user2", "module_user3"]
}

module "module_iam_user" {
  source = "./modules/iam/"

  count       = length(var.module_name)
  module_user = var.module_name[count.index]
}
```




### 条件分岐
- 三項演算子を用いて条件分岐を実現している。

```hcl:maintf
variable "count_ternary_operator" {
  type    = bool
  default = true
}

resource "aws_instance" "count_ternary_operator" {
  count         = var.count_ternary_operator ? 1 : 0
  instance_type = "t2.micro"
  ami           = "ami-027a31eff54f1fe4c"
}

resource "aws_instance" "count_ternary_operator2" {
  count         = var.count_ternary_operator ? 1 : 0
  instance_type = "t2.micro"
  ami           = "ami-027a31eff54f1fe4c"
}

output "count_instance_arn2" {
  value = one(concat(
    var.count_ternary_operator
    ? aws_instance.count_ternary_operator[*].arn
    : aws_instance.count_ternary_operator2[*].arn
  ))
}
```

- moduleを用いた内容
```hcl:./modules/count_instance/ec2.tf
variable "count_ternary_operator_module" {
  type = bool
}

resource "aws_instance" "count_ternary_operator_moudle" {
  count         = var.count_ternary_operator_module ? 1 : 0
  instance_type = "t3.micro"
  ami           = "ami-027a31eff54f1fe4c"

  tags = {
    Name = "module-${count.index}"
  }
}

```

```hcl:main.tf
module "count_ternary_operator_moudle" {
  source                        = "./modules/count_instance/"
  count_ternary_operator_module = true
}
```

