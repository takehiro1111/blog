# terraform {
#     required_version = "1.6.5" // 使用するterraform のバージョンを設定 

#     required_providers {
#         aws = {
#         source ="hashicorp/aws"//プロバイダーとしてAWSを使用する事を明示的に設定
#         version = "5.30.0" 
#         }
#     }

#     // テスト用のため、state ファイルをローカル環境で保管。 // state ファイルの説明は長くなるため本記事では割愛。
#      backend "local" {
#         path = "./backend/terraform-state" 
#     }

# }

# provider "aws" {
#     region ="ap-northeast-1"//東京リージョンをデフォルトリージョンに 指定。
#     profile = "test" // CLI や SDK で API 接続可能な認証ユーザ名を設定。 
#                     // AWS CLI の場合は、aws configureで設定したprofile名。
#     default_tags { 
#         tags = {
#          env = local.environment // 全リソース共通で付与したいタグを設定
#         }
#     }
# }

# locals  {
#     environment = "dev"
# }

# resource "aws_vpc" "test" {
#     cidr_block = "10.0.0.0/16"

#     tags = {
#         Name = "test-vpc"
#     } 
# }

# // data ブロックで取得したアカウント ID を外部向きに出力する設定 
# output "account_id" {
#     value = data.aws_caller_identity.current.account_id 
# }
# // resource ブロックで取得した VPC ID を外部向きに出力する設定 
# output "vpc_id" {
#     value = data.aws_vpc.test.id
# }

# locals {
#     ami ="ami-0dafcef159a1fc745"//AmazonLinux2のAMIを変数で 定義
#     type = "t2.micro" // インスタンスタイプの定義 
# }

# resource "aws_instance" "test" {
#     ami = local.ami
#     instance_type = local.type
# }

# variable "vpc_cidr" {
#     type = string
#     default = "192.168.0.0/24"
# } 

# resource "aws_vpc" "test" { 
#     cidr_block = var.vpc_cidr // variable変数の値が代入される。
# }

# variable "env" { 
#     type = string 
#     default = ""
# }

