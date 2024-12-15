---
title: "【Python】ラムダ式関数（無名関数）
emoji: "🙌"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Python","ラムダ"]
published: true
---
![](/images/py_logo/python-logo-master-v3-TM.png)

## Pythonの書き方におけるラムダとは？
- 一行で短い関数を定義できるような書き方。
- 無名関数と呼ばれ、関数名を定義せず簡潔に関数として定義できる記法。
- 特に関数を一度しか使わない場合や、非常に単純な処理を行う場合にコードを簡潔に保てる。
- 記法 -> `lambda 引数1, 引数2, ..., 引数n: 式`
  - 通常の関数でのreturnやリスト内包表記と異なり、実際に返る値は明示的に記載しない。

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
    return list_arg.capitalize() # 頭文字を大文字にし、残りを小文字に変換するメソッド

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
- 以下の例では便宜的にprintを使用している。
  - returnは「関数の実行を終了し、値を呼び出し元に返す」ため、ループが途中終了してしまうため。
```py
l = ["Mon","tue","wed","Thu","fri","Sat","sun"]

def basic(list_args,context):
  for list_arg in list_args:
    return context(list_arg)

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

## map関数の使い方
- イテラブル（リストやタプルなど）のすべての要素に組み込み関数やlambda（ラムダ式、無名関数）、defで定義した関数などを適用できる。
- 第一引数に適用する関数（呼び出し可能オブジェクト）、第二引数にリストなどのイテラブルオブジェクトを指定
```py
l = [-3,-2,-1,0]

print(map(abs,l))  # <map object at 0x102b8e680>
print(type(map(abs, l))) # <class 'map'>
print(list((map(abs,l)))) # [3, 2, 1, 0]

l_str = ['Tokyo','Osaka']
print(list(map(len,l_str))) # [5, 5]


for i in map(abs,l):
  print(i) # 3 2 1 0

# mapとlambdaの組み合わせ
print(list(map(lambda x : x ** 2,l))) # [9, 4, 1, 0]
print

# mapとdefの関数を組み合わせ
def test(x):
  return x ** 2

print(list(map(test,l))) # [9, 4, 1, 0]

## 複数のイテラブルを引数に指定

t_1 = (1,2,3)
t_2 = (10,20,30)

print(tuple(map(lambda x,y : x * y, t_1,t_2))) # (10, 40, 90)
print([x * y for x,y in zip(t_1,t_2)]) # (10, 40, 90)
```

### numpyを用いた書き方
```py
import numpy as np

a = np.array([-2, -1, 0])
print(np.abs(a))
# [2 1 0]

print(a**2)
# [4 1 0]

a_1 = np.array([1, 2, 3])
a_2 = np.array([10, 20, 30])
print(a_1 * a_2)
# [10 40 90]
```

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
[
  {'name': 'Laptop', 'price': 1200}, 
  {'name': 'Tablet', 'price': 1200}, 
  {'name': 'Phone', 'price': 800}, 
  {'name': 'Monitor', 'price': 300}
]
```
