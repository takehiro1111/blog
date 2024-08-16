---
title: "【Python】クロージャ-の挙動"
emoji: "🐙"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Python","クロージャー"]
published: false
---

## 1.クロージャーとは？
- 関数内で定義された内部関数が、外部関数のスコープにある変数にアクセスできる性質を持つ関数のこと。
- 外部にある変数をクロージャー内に「閉じ込めて」保持することで、外部関数が終了した後でも、その変数を使うことができる。
&nbsp;
## 2.基礎編コード
```py
# 以下の場合、「inner_function()」がクロージャーになる。
# outer_function()が終了していても、「inner_function()」の中で`msg`の値は保持される。
def outer_function(msg):
    def inner_function(): 
        print(msg)
    return inner_function

my_closure = outer_function("Hello, World!")
my_closure() 

```
```shell:result
Hello, World!

```
&nbsp;
## 3.応用編コード
- この応用例では、counter 関数が count の状態を保持し続けるため、呼び出すたびにカウントが増える。
- 即ち、クロージャーが特定のデータ(`この場合count変数の値`)を保持し続けるということが分かる。
```py
# make_counter()が終了しても、counter()関数がcount変数を保持し、
# その後もcount変数を更新し続けるクロージャー
def make_counter():
    count = 0

    def counter():
        nonlocal count
        count += 1
        return count

    return counter


counter_a = make_counter()
counter_b = make_counter()

print(counter_a()) 
print(counter_a())
print(counter_a())
print('-------------------')
print(counter_b())
print(counter_b())
print(counter_b())

```
```shell:result
1
2
3
-------------------
1
2
3

```




