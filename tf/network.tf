# #===================================
# #VPC
# #===================================
# resource "aws_vpc" "test" {
#   cidr_block = var.cidr_block[0] //variables.tfの配列が0の値を設定

#   tags = {
#     Name = "test-vpc"
#   }
# }

# #===================================
# #InternetGateway
# #===================================
# resource "aws_internet_gateway" "test" {
#   vpc_id = aws_vpc.test.id //VPCのIDを参照。

#   tags = {
#     Name = "test-igw"
#   }
# }

# #===================================
# #Subnet
# #===================================
# resource "aws_subnet" "test" {
#   vpc_id                  = aws_vpc.test.id
#   cidr_block              = var.cidr_block[1] //variables.tfの配列が1の値を設定
#   availability_zone       = local.az          // locals.tfのazの値を設定
#   map_public_ip_on_launch = false

#   tags = {
#     Name = "test-subent"
#   }
# }

# #===================================
# #Route Table
# #===================================
# resource "aws_route_table" "test" {
#   vpc_id = aws_vpc.test.id

#   route {
#     cidr_block = local.internet
#     gateway_id = aws_internet_gateway.test.id
#   }

#   tags = {
#     Name = "test-route"
#   }
# }

# resource "aws_route_table_association" "test" {
#   subnet_id      = aws_subnet.test.id
#   route_table_id = aws_route_table.test.id
# }