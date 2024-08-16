---
title: "【Python】デコレーターの挙動"
emoji: "💨"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Python","デコレーター"]
published: true
---
![](/images/py_logo/python-logo-master-v3-TM.png)

## デコレーターの使い方
### デコレーターとは?
- 関数の中で別の関数を呼び出す際に前後に処理を追加したり呼び出す側で定義自体を変更することなく、関数を呼び出せることで関数の動作を拡張できる機能。

### `@`を使用せず手動で適用する場合
```py
def my_decorator(func):
    def wrapper():
      print("start")
      func()
      print("stop")
    return wrapper

def say_hello():
    print("Hello!")

# 手動でデコレーターを適用
say_hello = my_decorator(say_hello)

# デコレーターが適用された関数を呼び出す
say_hello()

```

```shell:result
start
Hello!
stop
```

## 「`@`」を使用する場合
### イメージ
-  `say_hello`を`my_decorator`でラップして包み込むイメージ。
具体有的には、`my_decorator`が`say_hello`を引数として受け取り、その内部でラップすることで`wrapper`関数を作り出す。
```py
def my_decorator(func):
    def wrapper():
      print("start")
      func()
      print("stop")
    return wrapper

# 「@{呼び出す側の関数}」でよしなに適用してくれる。
@my_decorator
def say_hello():
    print("Hello!")

say_hello()
```

```shell:result
start
Hello!
stop
```


### デコレーターを複数の関数へ適用する使い方
```py
def my_decorator(func):
    def wrapper():
        print("start")
        func()
        print("stop")
    return wrapper

@my_decorator
def say_hello():
    print("Hello!")

@my_decorator
def say_goodbye():
    print("Goodbye!")

@my_decorator
def say_thanks():
    print("Thanks!")

# 関数を呼び出す
say_hello()
say_goodbye()
say_thanks()
```

```shell:result
start
Hello!
stop
start
Goodbye!
stop
start
Thanks!
stop
```


## 複数のデコレーターを1つの関数へ適用する場合
- まず、デコレーターを適用する順序で処理が変わってくる。
  - 上段(上位)のデコレーターのなかに下段(下位)のデコレーターが入り、その中で関数が二重で包み込まれるイメージ。
```py
def my_decorator(func):
    def wrapper():
        print("start")
        func()
        print("stop")
    return wrapper

def my_decorator_2(func):
    def wrapper():
        print("first")
        func()
        print("second")
    return wrapper

@my_decorator
@my_decorator_2
def say_hello():
    print("Hello!")

# 関数を呼び出す
say_hello()
```

```shell:result
start
first
Hello!
second
stop

```

### デコレコレーターの適用順序を変更
```py
def my_decorator(func):
    def wrapper():
        print("start")
        func()
        print("stop")
    return wrapper

def my_decorator_2(func):
    def wrapper():
        print("first")
        func()
        print("second")
    return wrapper

# デコレーターを適用する順序を逆にする場合
@my_decorator_2
@my_decorator
def say_hello():
    print("Hello!")

# 関数を呼び出す
say_hello()
```

```shell:result
first
start
Hello!
stop
second

```
