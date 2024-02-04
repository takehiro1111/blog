---
title: "[AWS/Linux]EBSボリュームのリサイズ方法"
emoji: "💭"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["aws","EC2","EBS","Linux","インフラエンジニア"]
published: true
---

![](/images/ebs_resize/aws_logo.png =300x)

## 記事を書いた経緯
- エンジニアになって初案件がオンプレからAWSへの移行でその際に対応したのですが、手順をほぼ忘れたなと思いブログに残したいと思ったためです。
&nbsp;

## 目的
- EC2インスタンスにアタッチしているEBSボリュームのサイズ変更をOS側に適用したい。
&nbsp;

## 前提の環境
- OS:Amazon Linux2
- ストレージ:EBSボリューム
- ファイルシステム:xfs
- ブロックデバイス:/dev/xvda1
- サイズ:`20GB`→`30GB`への変更
- EC2インスタンスは作成済みでSSHやセッションマネージャーでログインが可能である状態。
&nbsp;

## AWS Management Console での作業
### ■リサイズ前のEBSボリューム
![](/images/ebs_resize/df_h.png)
![](/images/ebs_resize/lsblk.png)
![](/images/ebs_resize/ebs_before.png)

### ■EBSボリュームサイズの修正

![](/images/ebs_resize/volume_change1.png)
![](/images/ebs_resize/modify_volume.png)

- コンソール画面上からEBSボリュームのサイズが変更になっている事を確認。
![](/images/ebs_resize/after_change.png)

- サーバー上でもEBSボリュームのサイズが変更した事を確認。
  マウントしているファイルシステムにも反映していく必要があります。
![](/images/ebs_resize/shell_after.png)

:::message
`lsblk`:OSが認識しているブロックデバイス(HDD,SSD,USB等)を表示するコマンド。
:::

:::message
`df -hT`:ファイルシステムのディスク使用量と利用可能な空き容量を表示するコマンド。`-h`で人間が読みやすい表示に加工し、`-T`でファイルシステムのタイプを表示。
:::
&nbsp;
## サーバー(EC2インスタンス) での作業
- OSレベルでのパーティションサイズの変更とファイルシステムの拡張は自動的には行われないため、手動で対応する必要がある。

#### ①パーティションの拡張
##### `growpart`
- cloud-utilsパッケージに含まれており、主にクラウド環境で動作するインスタンスのディスクサイズの動的な変更をするために利用されます。

```bash:bash
sudo growpart /dev/xvda1
```

#### ②ファイルシステムの拡張
##### `xfs_grows`
- XFSファイルシステムを使用しているパーティションのファイルシステムのサイズを拡張するために使用されます。
- 今回の場合はマウントポイントが`/(ルートファイルシステム)`のため、引数は`/`としています。
```bash:bash
sudo xfs_growfs /
```
&nbsp;
:::message
補足:ファイルシステムが`ext4`の場合
:::
- ファイルシステムの生合成をチェック
```bash:bash
sudo e2fsck -f /dev/xvda1
```
- ファイルシステムの拡張
```bash:bash
sudo resize2fs /dev/xvda1
```

#### ③EBSボリュームのサイズ変更が適用されたか確認
- /dev/xvda1のサイズが20GBから30GBに増加されているため、変更が適用されている事が確認できます。
![](/images/ebs_resize/after_all.png)
