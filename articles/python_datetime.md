---
title: "[Python]datetimeモジュールの使い方"
emoji: "🐡"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ['python']
published: true
---

![](/images/py_logo/python-logo-master-v3-TM.png)

## 1.datetimeモジュールとは？
### [ドキュメントの記載](https://docs.python.org/ja/3/library/datetime.html)
> datetime モジュールは、日付や時刻を操作するためのクラスを提供しています。
日付や時刻に対する算術がサポートされている一方、実装では出力のフォーマットや操作のための効率的な属性の抽出に重点を置いています。

### タイムゾーンの解決
> aware オブジェクトを必要とするアプリケーションのために、 datetime と time オブジェクトは追加のタイムゾーン情報の属性 tzinfo を持ちます。 tzinfo には抽象クラス tzinfo のサブクラスのインスタンスを設定できます。 これらの tzinfo オブジェクトは UTC 時間からのオフセットやタイムゾーンの名前、夏時間が実施されるかどうかの情報を保持しています。

>  tzinfo クラスである timezone クラスが datetime モジュールで提供されています。 timezone クラスは、UTCからのオフセットが固定である単純なタイムゾーン（例えばUTCそれ自体）、および北アメリカにおける東部標準時（EST）／東部夏時間（EDT）のような単純ではないタイムゾーンの両方を表現できます。

## 2.各オブジェクトの使い方
### `datetime.date`
- 年、月、日を表現するシンプルな日付オブジェクト。
- 属性
  - `year`, `month`, `day `

```py
date = datetime.date(year=2024,month=12,day=21)
print(date.strftime('%Y/%m/%d')) # 2024/12/21
```

### `datetime.time`
- 時、分、秒、マイクロ秒を表現する時刻オブジェクト。
- 属性
  -  `hour`, `minute`, `second`, `microsecond`, `tzinfo`

```py
import datetime
import zoneinfo

TZ = zoneinfo.ZoneInfo("Asia/Tokyo")
time = datetime.time(hour=9,minute=3,second=5,microsecond=10,tzinfo=TZ)
print(time)
```

### `datetime.datetime`
- 日付と時刻の両方を組み合わせたオブジェクト。
-  `year`, `month`, `day`, `hour`, `minute`, `second`, `microsecond`, `tzinfo`

```py
import datetime

now = datetime.datetime.now(UTC)
print(now) # 2024-12-21 05:33:36.563305+00:00
print(now.isoformat()) # 国際標準規格での表示 2024-12-21T05:33:36.563305+00:00
print(now.strftime('%Y/%m/%d-%H:%M:%S')) # 2024/12/21-05:33:36

# 現在の日時をJSTで取得
now_jst = datetime.datetime.now(JST)
print(now_jst) # 2024-12-21 14:40:00.835475+09:00
print(now_jst.strftime('%Y/%m/%d-%H:%M:%S')) # 2024/12/21-14:40:00
```

### `datetime.timedelta`
- 時間の差や期間を表現するオブジェクト。
```py
import datetime

# 現在の日付と時間
now = datetime.datetime.now()
print("現在の日時:", now) # 現在の日時: 2024-12-21 15:08:34.591238

# 5日後の日時
future_date = now + datetime.timedelta(days=5)
print("5日後の日時:", future_date) # 5日後の日時: 2024-12-26 15:08:34.591238

# 3日前の日時
past_date = now - datetime.timedelta(days=3)
print("3日前の日時:", past_date) # 3日前の日時: 2024-12-18 15:08:34.591238

# 二つの日付の差を計算
date1 = datetime.datetime(2024, 12, 21, 12, 0, 0)
date2 = datetime.datetime(2024, 12, 25, 18, 30, 0)

# Pythonが内部でtimedeltaを生成して差を表現している。
delta = date2 - date1
print(f"日数: {delta.days} 日")  # 日数: 4 日
print(f"総秒数: {delta.total_seconds()} 秒")  # 総秒数: 384600.0 秒
```


### `datetime.tzinfo`
- タイムゾーン情報を提供する基底クラス（通常は直接使用しない）。

```py
import datetime
import zoneinfo

TZ = zoneinfo.ZoneInfo("Asia/Tokyo")
date_time = datetime.datetime(year=2024, month=12, day=21, hour=9,minute=3,second=5,microsecond=10,tzinfo=TZ)
print(date_time.strftime('%Y/%m/%d-%p%H:%M:%S:%f(%Z)')) # 2024/12/21-AM09:03:05:000010(JST)
```

### `datetime.timezone`
- 固定オフセットのタイムゾーン情報を提供するクラス。
```py
import datetime

now = datetime.datetime.now(UTC)
print(now) # 2024-12-21 13:53:44.904444 ※実行時の数値
```
::: message alert
> バージョン 3.12 で非推奨: 代わりに UTC で datetime.now() を使用してください。<[参照](https://docs.python.org/ja/3/library/datetime.html#datetime.datetime.tzinfo:~:text=%E3%83%90%E3%83%BC%E3%82%B8%E3%83%A7%E3%83%B3%203.12%20%E3%81%A7%E9%9D%9E%E6%8E%A8%E5%A5%A8%3A%20%E4%BB%A3%E3%82%8F%E3%82%8A%E3%81%AB%20UTC%20%E3%81%A7%20datetime.now()%20%E3%82%92%E4%BD%BF%E7%94%A8%E3%81%97%E3%81%A6%E3%81%8F%E3%81%A0%E3%81%95%E3%81%84%E3%80%82)>

> datetime.timezoneは固定オフセットのため、動的な夏時間（DST）対応にはzoneinfoを使用してください。
:::

- JSTの取得
```py
import datetime

now_jst = datetime.datetime.now(JST)
print(now_jst)  # 2024-12-21 15:34:21.927748+09:00
print(now_jst.strftime('%Y/%m/%d-%H:%M:%S')) # 2024/12/21-15:34:2115:34:21
```
## 3.`strftime`と`strptime`メソッドの違い
| 特徴      | strftime                           | strptime                           |
|-----------|------------------------------------|------------------------------------|
| 役割      | 日付オブジェクトを文字列に変換     | 文字列を日付オブジェクトに解析     |
| 入力      | datetime、date、time などのオブジェクト | 日時を表す文字列                   |
| 出力      | フォーマットされた文字列           | datetime オブジェクト              |
| 使用例    | フォーマットされた日時を表示       | 日時文字列を解析してプログラムで利用 |

### `strftime`メソッド
```py
import datetime

# 現在の日時
now = datetime.datetime.now()

# フォーマット指定で文字列に変換
formatted_date = now.strftime('%Y/%m/%d %H:%M:%S')
print(f"strftime の結果: {formatted_date}")  # 2024/04/27 15:30:45
```

### `strptime`メソッド
```py
import datetime

# 日時を表す文字列
date_str = '2024/12/21 15:30:45'

# 文字列を解析してdatetimeオブジェクトに変換
parsed_date = datetime.datetime.strptime(date_str, '%Y/%m/%d %H:%M:%S')
print(f"strptime の結果: {parsed_date}")  # 2024-04-27 15:30:45
```

# 参考
https://docs.python.org/ja/3/library/datetime.html
https://note.nkmk.me/python-datetime-usage/
https://note.nkmk.me/python-datetime-timedelta-conversion/
