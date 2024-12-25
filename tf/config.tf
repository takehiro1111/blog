#===================================
#Terraform block
#===================================
terraform {
  required_version = "1.10.3" //使用するterraformのバージョンを設定
  required_providers {
    aws = {
      source  = "hashicorp/aws" //プロバイダーとしてAWSを使用する事を明示的に設定
      version = "5.82.2"
    }
  }

  // テスト用のため、stateファイルはlocalで対応。(ここは説明していないので無視して下さい。)
  backend "local" {
    path = "tfstate/terraform-state"
  }

  # backend "s3" {
  #   bucket  = "backend-common"
  #   key     = "main"
  #   region  = "ap-northeast-1"
  #   acl     = "private"
  #   encrypt = true
  # }
}

#===================================
#Provider block
#===================================
provider "aws" {
  region  = "ap-northeast-1" //東京リージョンをデフォルトリージョンに指定。
  profile = "sekigaku"       // CLIやSDKでAPI接続可能な認証ユーザ名を設定。
  // AWS CLIの場合は、aws configureで設定したprofile名。
}