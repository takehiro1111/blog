---
title: "【Python】ラムダの書き方、使用例(AWSのLambda関数ではない)"
emoji: "🙌"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Python","ラムダ"]
published: true
---
![](/images/py_logo/python-logo-master-v3-TM.png)

## Pythonの書き方におけるラムダとは？
- 一行で短い関数を定義できるような書き方q。
- 特に関数を一度しか使わない場合や、非常に単純な処理を行う場合にコードを簡潔に保てる。

## 基本的なコード例

### ラムダを使用しない場合
- 関数を無駄に書いてしまうので、コード量が多くなり可読性が落ちる。
```py
l = ["Mon","tue","wed","Thu","fri","Sat","sun"]

def basic(list_args,context):
    for list_arg in list_args:
        print(context(list_arg))

# 複数の処理を行う場合は、更に関数を追記する必要がある。
def sample_basic(list_arg):
    return list_arg.capitalize() # 文字を大文字にし、残りを小文字に変換するメソッド

basic(l,sample_basic)
```

```shell:result
Mon
Tue
Wed
Thu
Fri
Sat
Sun
```

&nbsp;
### ラムダを使用する場合
- 関数で2行記載していた内容を省略できて引数に直接定義出来る。
```py
def basic(list_args,context):
  for list_arg in list_args:
    print(context(list_arg))

basic(l,lambda list_arg: list_arg.capitalize())

```

```shell:result
Mon
Tue
Wed
Thu
Fri
Sat
Sun
```
&nbsp;
## 少し応用的な使い方
- ラムダを用いて複数処理を実行する。
```py
# 1-10の数値を偶数だけを抽出し2乗する
numbers = list(range(1,11))
squared_even_numbers = list(map(lambda x: x**2, filter(lambda x: x % 2 == 0, numbers)))

print(squared_even_numbers)

```

```shell:result
[4, 16, 36, 64, 100]
```

&nbsp;
- 複数の条件を組み合わせたカスタムソートを実施。
```py
products = [
    {"name": "Laptop", "price": 1200},
    {"name": "Phone", "price": 800},
    {"name": "Tablet", "price": 1200},
    {"name": "Monitor", "price": 300}
]

# ソートする基準をラムダを用いて定義している。
# 価格は降順、価格が同じ場合は名前のアルファベット順(昇順)でソート
sorted_products = sorted(products, key = lambda product: (-product['price'], product['name']))

print(sorted_products)
```

```shell:result
[{'name': 'Laptop', 'price': 1200}, {'name': 'Tablet', 'price': 1200}, {'name': 'Phone', 'price': 800}, {'name': 'Monitor', 'price': 300}]
```
