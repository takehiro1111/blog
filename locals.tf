/* locals {
  environment = "dev" // リソースを構築するデフォルトの環境を記載

  az = "ap-northeast-1a" // サブネットを設定するAZを定義

  internet = "0.0.0.0/0" // インターネットゲートウェイ,セキュリティグループのアウトバウンドで下記CIDRを指定

  ami = "ami-0dafcef159a1fc745"
} */