---
title: "AWSBackupからEBSボリュームを復元する方法"
emoji: "🐥"
type: "tech" # tech: 技術記事 / idea: アイデア
topics:  ["aws","EC2","EBS","Linux","インフラエンジニア"]
published: false
---

![](/images/ebs_resize/aws_logo.png =300x)

## 記事を書いた経緯
- エンジニアになって初めての案件で対応したタスクですが、整理してブログに残したいなと何となく思い書きました。
&nbsp;

## 目的
- AWS Backupで
&nbsp;

## 前提の環境
- OS:Amazon Linux2
- ストレージ:EBSボリューム
- ファイルシステム:xfs
- ブロックデバイス:/dev/xvda1
- サイズ:`20GB`→`30GB`への変更
- EC2インスタンスは作成済みでSSHやセッションマネージャーでログインが可能である状態。
&nbsp;