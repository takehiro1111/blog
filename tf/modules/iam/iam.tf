variable "module_user" {
  type    = string
  default = ""
}

resource "aws_iam_user" "test_module1" {
  name = var.module_user
  path = "/system/"
}

output "aws_iam_user" {
  value = aws_iam_user.test_module1.arn
}