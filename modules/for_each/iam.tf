variable "user_name" {
    type = string
}


resource "aws_iam_user" "test_2" {
  name  = var.user_name
  path  = "/each_module/"
}

output "iam_user_name_all2" {
  value = aws_iam_user.test_2.arn
  // for_eachだと出力がmap形式になるため、values関数で値のみを抜き出してスプレット形式で配列の全ての要素を取ってくる。
}