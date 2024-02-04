---
title: "[AWS/Linux]EBSのリサイズ方法"
emoji: "💭"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["aws","EC2","EBS","Linux","インフラエンジニア"]
published: false
---

![](/images/ebs_resize/aws_logo.png)

## 記事を書いた経緯
- エンジニアになって初案件がオンプレからAWSへの移行でその際に対応したのですが、手順をほぼ忘れたなと思いブログに残したいと思ったためです。
&nbsp;

## 本記事を読み終わった時のゴール
- EC2インスタンスにアタッチしているEBSボリュームを必要な際にリサイズ出来る事。
&nbsp;

## 前提の環境
- OS:Amazon Linux2
- EC2インスタンスは作成済みでSSHやセッションマネージャーでログインが可能である状態。
&nbsp;

## 本編
### リサイズ前のEBSボリューム
![](/images/ebs_resize/df_h.png)
![](/images/ebs_resize/lsblk.png)
![](/images/ebs_resize/ebs_before.png)

### EBSボリュームサイズの修正

![](/images/ebs_resize/volume_change.png)
![](/images/ebs_resize/modify_volume.png)

- コンソール画面上からEBSボリュームのサイズが変更になっている事を確認。
![](/images/ebs_resize/after_change.png)

- サーバー上でもEBSボリュームのサイズが変更した事を確認。
  マウントしているファイルシステムにも反映していく必要があります。
![](/images/ebs_resize/shell_after.png)

#### パーティションの拡張
```bash:bash
sudo growpart /dev/xvda 1
```

#### ファイルシステムの拡張
```bash:bash
sudo xfs_growfs /
```

#### EBSボリュームのサイズ変更が適用されたか確認
- /dev/xvda1のサイズが20GBから30GBに増加されているため、変更が適用されている。
![](/images/ebs_resize/after_all.png)


