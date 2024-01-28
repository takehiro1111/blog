/* resource "aws_instance" "test" {
  ami                         = local.ami // 「Amazon Linux 2 AMI (HVM) - Kernel 5.10, SSD Volume Type」のAMI
  subnet_id                   = aws_subnet.test.id
  instance_type               = "t2.micro"
  vpc_security_group_ids      = [aws_security_group.test.id]
  associate_public_ip_address = true // グローバルIPの有効化

  //ユーザーデータでEC2インスタンスの中でhttpdが起動してドキュメントルートにindex.htmlファイルが置かれるよう設定
  user_data = <<-EOF
                #!/bin/bash
                yum update -y
                yum install -y httpd
                systemctl start httpd
                systemctl enable httpd
                echo "Hello World!" > /var/www/html/index.html
                EOF
  //EC2インスタンスにデフォルトでアタッチされるEBSボリュームの設定
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = false
    encrypted             = true
  }

  tags = {
    Name = "web-instance"
  }
} */

# resource "aws_instance" "test_blog" {
#   ami = "ami-0dafcef159a1fc745"
#   instance_type = "t2.micro"
# }