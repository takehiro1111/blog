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