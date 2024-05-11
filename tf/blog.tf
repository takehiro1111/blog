# countのメリット
// 三項演算子が使用できる

# countのデメリット
// リソース単位でしか使えず、インラインブロックには適用できない。
// 配列内で要素の位置が変更になると意図しないリソースの削除や修正が発生する。

# count ループ
resource "aws_iam_user" "test" {
  count = 2
  name  = "test-${count.index}"
}

# 配列の取り出し方にビルトイン関数を使用した使い方
variable "test" {
  type    = list(string)
  default = ["test_a","test_c"]
}

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

# moduleを用いたバージョン
module "count_ternary_operator_moudle" {
  source                        = "./modules/count_instance/"
  count_ternary_operator_module = true
}


# for_each ループ

variable "map" {
  type    = map(string)
  default = {
    "a" = "map_1", 
    #"b" = "map_2", 
    "c" = "map_3"
  }
}

resource "aws_iam_user" "test_2" {
  for_each =  toset(values(var.map)) //values関数で値のみを抜き出し、それをsetに直して重複を除いている。
  name  = each.value
  path  = "/each/"
}

output "iam_user_name_all2" {
  value = values(aws_iam_user.test_2)[*].name
  // for_eachだと出力がmap形式になるため、values関数で値のみを抜き出してスプレット形式で配列の全ての要素を取ってくる。
}

// リソースのコピーにはcountではなく、for_eachを使用するべき。
// countだと削除時に配列の順番を入れ替わるため、削除対象以外のリソースにも影響が出てしまう。 P146
// for_eachだとコードの中で1つの要素を削除するとそれのみがさくじょされるだけ(P149)

# module
module "module_for_each_map" {
    source = "./modules/for_each/"
    for_each = toset(values(var.module_map2))
    user_name = each.value
}


// for_eachでインラインブロックを複数作成する
variable "module_map2" {
  type    = map(string)
  default = {
    "a" = "module_map_1", 
    "b" = "module_map_2", 
    "c" = "module_map_3"
  }
}

resource "aws_autoscaling_group" "default" {
  min_size = 0
  max_size = 0
  availability_zones = ["ap-northeast-1a"]

  launch_template {
    id      = aws_launch_template.foobar.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = {
      for k, v in var.module_map2 : k => upper(v)
      if k != "a"
    }

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }
}

# locals {
#   my_tags = {
#     Name        = "my-asg"
#     Component   = "user-service"
#     Environment = "dev"
#   }
# }

resource "aws_launch_template" "foobar" {
  name_prefix   = "foobar"
  image_id      = "ami-027a31eff54f1fe4c"
  instance_type = "t2.micro"
}


# resource "aws_autoscaling_group" "example" {
#   availability_zones = ["ap-northeast-1a"]
#   desired_capacity   = 1
#   max_size           = 1
#   min_size           = 1
#   launch_template {
#     id      = aws_launch_template.foobar.id
#     version = "$Latest"
#   }

#   dynamic "tag" {
#     for_each = local.my_tags

#     content {
#       key                 = tag.key
#       value               = tag.value
#       propagate_at_launch = true
#     }
#   }
# }
