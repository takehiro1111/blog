# countのメリット
// 三項演算子が使用できる

# countのデメリット
// リソース単位でしか使えず、インラインブロックには適用できない。
// 配列内で要素の位置が変更になると意図しないリソースの削除や修正が発生する。

# count ループ
variable "test" {
  type    = list(string)
  default = ["test_a", "test_b", "test_c"]
}

resource "aws_iam_user" "test" {
  count = 2
  name  = "test-${count.index}"
}

// 配列の取り出し方にビルトイン関数を使用した使い方
resource "aws_iam_user" "test_1" {
  count = length(var.test) //length関数で配列の要素数を返す = 3
  name  = var.test[count.index]
  path  = "/system/"
}

output "iam_user_name_all" {
  value = aws_iam_user.test_1[*].name // スプレット形式で配列の全ての要素を取ってくる。
}


# moduleからの呼び出しも可能
variable "module_name" {
  type    = list(string)
  default = ["module_user1", "module_user2", "module_user3"]
}

module "module_iam_user" {
  source = "./modules/iam/"

  count       = length(var.module_name)
  module_user = var.module_name[count.index]
}

# count 条件分岐
// 条件付きリソースに使用する。
// 三項演算子を用いる
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

output "count_instance_arn" {
  value = (
    var.count_ternary_operator
    ? aws_instance.count_ternary_operator[0].arn
    : aws_instance.count_ternary_operator2[0].arn
  )
}

output "count_instance_arn2" {
  value = one(concat(
    var.count_ternary_operator
    ? aws_instance.count_ternary_operator[*].arn
    : aws_instance.count_ternary_operator2[*].arn
  ))
}

// moduleを用いたバージョン
module "count_ternary_operator_moudle" {
  source                        = "./modules/count_instance/"
  count_ternary_operator_module = true
}
