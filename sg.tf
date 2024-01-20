#=========================================
# Security Group
#=========================================
resource "aws_security_group" "test" {
  description = "sg for http"
  name        = "test"
  vpc_id      = aws_vpc.test.id

  tags = {
    Name = "test-sg"
  }
}

//セキュリティグループのインバウンドルールの設定
resource "aws_vpc_security_group_ingress_rule" "http" {
  description       = "inboound rule for http"
  security_group_id = aws_security_group.test.id
  cidr_ipv4         = local.internet
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"

  tags = {
    Name = "in-http"
  }
}

//セキュリティグループのアウトバウンドルールの設定
resource "aws_vpc_security_group_egress_rule" "http" {
  description       = "outboound rule for http"
  security_group_id = aws_security_group.test.id
  cidr_ipv4         = local.internet
  ip_protocol       = "all"

  tags = {
    Name = "out-http"
  }
}