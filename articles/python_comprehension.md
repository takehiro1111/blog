---
title: "[Python]内包表記(リスト,辞書,集合,ジェネレーター)"
emoji: "🐈"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Python","リスト内包表記","辞書内包表記","集合内包表記","ジェネレーター式"]
published: true
---

![](/images/py_logo/python-logo-master-v3-TM.png)
## 内包表記とは？
- データ構造を簡潔に表現するための書き方のこと。
  - 内包表記を使用することでコードの記述が簡潔になるため良い。

## リスト内包補表記
- 基礎的な書き方
```py
# 条件付きのforループでリストを生成
list_comprehension = [i for i in range(1,10) if i % 2 == 0]

print(type(list_comprehension))
print(list_comprehension)
```

```shell:result
<class 'list'>
[2, 4, 6, 8]
```

- 複数のリストから単一のリストを生成する例。
```py
l_id = [1,2,3]
l_name = ["Sato","Suzuki","Tanaka"]

list_comprehension = [i for i in zip(l_id,l_name) ]

print(list_comprehension)
```

```shell:result
[(1, 'Sato'), (2, 'Suzuki'), (3, 'Tanaka')]
```

## 辞書内包表記
```py
l_id = [1,2,3]
l_name = ["Sato","Suzuki","Tanaka"]

dict_comprehension = {k:v for k,v in zip(l_id,l_name)}

print(dict_comprehension)
```

```shell:result
{1: 'Sato', 2: 'Suzuki', 3: 'Tanaka'}
```

## 集合内包表記
```py
l_name = ["Sato","Suzuki","Tanaka","Hashimoto","Suzuki"]

set_comprehension = {name for name in l_name}

print(set_comprehension)
```

```shell:result
# 集合のため順序が保証されておらず、重複分の要素が排除されている。
{'Hashimoto', 'Tanaka', 'Suzuki', 'Sato'}
```
## ジェネレーター式
```py
# 内包表記を使用しない場合は関数を記述するので記述量が多くなる。
# def gen():
#     for i in range(1,6):
#         yield i * 2
# gen = gen()

gen = (x * 2 for x in range(1,6))
print(next(gen))
print(next(gen))
print(next(gen))
print(next(gen))
print(next(gen))
```
```shell:result
2
4
6
8
10
```
