---
title: "[AWS/Linux]EBSボリュームを追加でEC2インスタンスへアタッチ,マウントする"
emoji: "🍣"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["aws","EC2","EBS","Linux","Terraform"]
published: true
---

![](/images/ebs_additional/amazon-ebs.png =600x)

## 目的
- EC２インスタンスに追加でEBSボリュームをアタッチし、EC2の中でマウントする事でOSにもデバイス(EBSボリューム)を認識させる。
&nbsp;

## 前提の環境
- OS:`Amazon Linux2`
- ストレージ:`EBSボリューム`
- ファイルシステム:`ext4`,`xfs`
- ブロックデバイス:`/dev/xvdh`,`/dev/xvdf1`
- EC2インスタンスは作成済みで`SSH`や`セッションマネージャー`でログインが可能である状態。
- ファイルシステムで`ext4`,`xfs`の2種類を試したかったため、アタッチするEBSボリュームを2つ作成しています。
&nbsp;

## EBSボリュームのアタッチ
### Terraformで対応する場合

```hcl:main.tf
// EBSボリュームの作成
resource "aws_ebs_volume" "ebs_add_1" {
  availability_zone = "ap-northeast-1a"
  size              = 8 //無料の範囲内で設定。
  encrypted = true
  type = "gp3"
  tags = {
    Name = "zenn-aditional-vol-1"
  }
}

resource "aws_ebs_volume" "ebs_add_1" {
  availability_zone = "ap-northeast-1a"
  size              = 8 //無料の範囲内で設定。
  encrypted = true
  type = "gp3"
  tags = {
    Name = "zenn-aditionalvol-2"
  }
}

// 対象のEC2インスタンスへアタッチ
resource "aws_volume_attachment" "ebs_add_1" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.ebs_add_1.id
  instance_id = aws_instance.web_instance.id
  stop_instance_before_detaching = true
}

```

### AWS CLIで対応する場合
1.EBSボリュームの作成
```bash
aws ec2 create-volume --availability-zone ap-northeast-1a --size 8 --volume-type gp2
aws ec2 create-volume --availability-zone ap-northeast-1a --size 20 --volume-type gp2
```

2.作成したEBSボリュームの識別用に`Name`タグを作成
```bash
aws ec2 create-tags --resources ${volume-id} --tags Key=Name,Value=${volume-name}
```

2.EBSボリュームをEC2インスタンスへアタッチ
```bash
aws ec2 attach-volume --volume-id ${volume-id} --instance-id ${instance-id} --device ${device-name}
```

### コンソール画面で対応する場合
1. EBSボリュームの作成
- 今回はアタッチする目的でのみ作成するため、ボリュームサイズを無料の範囲内とし、
他項目はデフォルトで作成します。

![](/images/ebs_additional/new1.png)
![](/images/ebs_additional/new2.png)

2. EBSボリュームをEC2インスタンスへアタッチ
![](/images/ebs_additional/attach1.png)
![](/images/ebs_additional/attach2.png)
&nbsp;

:::message alert
私は以下内容で作成しているため、下記はそれ前提の記載があるかと思います。
`/dev/xvdf`:Terraformで作成
`/dev/xvdh1`:コンソール画面で作成
:::

## EC２インスタンスでのマウント対応
1. デバイスとファイルシステムの状態を確認。(現状はマウントされていないため、特に情報無し。)
```bash
df -hT
```
![](/images/ebs_additional/first_df_h.png)
&nbsp;

2. デバイスにファイルシステムを作成(フォーマット)
- 今回アタッチするボリュームにフォーマットするファイルシステムを作成。

```bash:ext4の場合(Terraformでアタッチ)
sudo mkfs -t ext4 /dev/xvdf
```

```bash:xfsの場合(コンソール画面でアタッチ)
sudo mkfs.xfs /dev/xvdh1
```
&nbsp;

3.マウントポイント用のディレクトリ作成
- 今回は`/data`,`/data2`にディスクをマウントするため作成。
```bash
sudo mkdir /data
```
```bash
sudo mkdir /data2
```
&nbsp;

4.マウント実施
```bash:ext4の場合(Terraformでアタッチ)
 sudo mount -t ext4 /dev/xvdh /data
```

```bash:xfsの場合(コンソール画面でアタッチ)
sudo mount -t xfs /dev/xvdf1 /data2
```
&nbsp;

5. `/etc/fstab`へファイルシステムの情報を追記
- OSが起動する際にどのデバイスをどのディレクトリにマウントするかを`fstab`の情報を確認して認識するため。

```bash
 vi /etc/fstab
```
![](/images/ebs_additional/fstab.png)

:::message
以下コマンドでデバイスのUUID等の情報を確認する事が出来る。
:::
```bash
sudo blkid
```

#### `/etc/fstab`の構成

| フィールド| 要素 | 値 |
| ---- | ---- | ---- |
| 第1フィールド | デバイスファイル名 or UUDI | `/dev/xvdf1` or `UUID={一意のID}` |
| 第2フィールド | マウントポイント | `/` , `/data` 等 |
| 第3フィールド | ファイルシステムの種類 | `ext2`,`ext3`,`ext4`,`xfs`,`nfs`等 |
| 第4フィールド | マウントオプション | `defaults`,`async`,`auto`,`noauto`,`nouser`,`user`等 |
| 第5フィールド | dumpフラグ | `0` or `1`(1だとdumpコマンドによるバックアップ対象になる) |
| 第6フィールド | OS起動時にfsckチェックを行うか | `0`(チェック無し),`1`(`/`の場合),`2以降`(その他) |

&nbsp;

6. 新規でアタッチしたEBSボリューム(ディスク)が`/data`,`/data2`にマウントされている事を確認し完了。
```bash
df -hT
```
![](/images/ebs_additional/last_confirmation.png)

```bash
lsblk
```
![](/images/ebs_additional/last_lsblk.png)
&nbsp;

## EBSボリュームをデタッチする方法
1.デバイスを取り外すため、ファイルシステムをマウントポイントからマウント解除。
```bash
umount /data
umount /data2
```

:::message
`umount`コマンドの引数は、`デバイス名` or `マウントポイント`の片方の指定で良い。
:::

2.データをディスクにフラッシュする。
- OSのメモリ(RAM)にキャッシュされている全ての未処理の入出力操作(I/O)を強制的にフラッシュし
ディスクに書き込む事でデータの安全性と生合成を確保する。
通常、OSはファイルシステムの書き込み操作をディスクではなく一時的にメモリ内にデータをキャッシュするため。(ディスクよりもメモリに書く方が高速なため、システムのパフォーマンスが向上するが、予期しないシャットダウンや災害等はリスクになる。)
```bash
sync
```

3.`/etc/fstab`の削除
システムが再起動した際に自動的にマウントされないように、`/etc/fstab`から該当するエントリを削除またはコメントアウトして無効化する。
```bash
vi /etc/fstab
```

4.EBSボリュームをEC２インスタンスからデタッチする。
- AWS CLIの場合
```zsh
aws ec2 detach-volume --volume-id ${volume-id1}
aws ec2 detach-volume --volume-id ${volume-id2}
```

- コンソール画面から実施する場合
![](/images/ebs_additional/detach_console1.png)
![](/images/ebs_additional/detach_console2.png)

:::message alert
アタッチしていない単体のEBSボリュームにも課金されるため、気になる方はEBSボリュームを削除してください。
:::

- EBSボリュームの削除
```bash
aws ec2 delete-volume --volume-id ${volume-id}
aws ec2 delete-volume --volume-id ${volume-id}
```

## 番外編
### 複数リソースまとめて実行する場合のシェルスクリプト
-  EBSボリュームの作成,アタッチ
```bash:./ebs_detach.sh
#!/bin/bash

# 設定項目
INSTANCE_ID="i-{id}" # アタッチするインスタンスID
AVAILABILITY_ZONE="ap-northeast-1a" # ボリュームを作成するアベイラビリティーゾーン
VOLUME_SIZE="10" # 作成するボリュームのサイズ（GB）
VOLUME_TYPE="gp2" # ボリュームタイプ
NUMBER_OF_VOLUMES=2 # 作成するボリュームの数

# ボリュームを作成してアタッチ
for ((i=0; i<NUMBER_OF_VOLUMES; i++))
do
    # EBSボリュームを作成
    VOLUME_ID=$(aws ec2 create-volume --availability-zone $AVAILABILITY_ZONE --size $VOLUME_SIZE --volume-type $VOLUME_TYPE --query 'VolumeId' --output text)
    echo "Created volume: $VOLUME_ID"

    # ボリュームが利用可能になるまで待機
    aws ec2 wait volume-available --volume-ids $VOLUME_ID
    echo "Volume $VOLUME_ID is now available."

    # EBSボリュームをインスタンスにアタッチ
    DEVICE_NAME="/dev/sd$(echo $i | awk '{printf "%c", 102+$1}')" # デバイス名を /dev/sdf, /dev/sdgとする。
    aws ec2 attach-volume --volume-id $VOLUME_ID --instance-id $INSTANCE_ID --device $DEVICE_NAME
    echo "Attaching volume $VOLUME_ID to $INSTANCE_ID on $DEVICE_NAME"
done


```

  - EBSボリュームのデタッチ,削除
```bash:./ebs_detach_delete.sh
#!/bin/bash

# デタッチして削除するボリュームIDのリスト
volume_ids=("vol-{id1}" "vol-{id2}" "vol-{id2}")

# 各ボリュームをデタッチして削除
for volume_id in "${volume_ids[@]}"; do
    # ボリュームをデタッチ
    aws ec2 detach-volume --volume-id $volume_id
    echo "Detached volume $volume_id"

    # ボリュームが利用可能になるまで待機
    aws ec2 wait volume-available --volume-ids $volume_id
    echo "Volume $volume_id is now available."

    # ボリュームを削除
    aws ec2 delete-volume --volume-id $volume_id
    echo "Deleted volume $volume_id"
done

```

## 完