---
title: ""
emoji: "🎃"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: []
published: false
---
![](/images/py_logo/python-logo-master-v3-TM.png)

## `@dataclass`とは？
- デコレータの一種
  - イニシャライザでフィールドに引数の値を設定する処理を自動で生成してくれる。

### 通常の設定
```py
class Nouse():
  def __init__(self,name,age,gender,job)
    self.name = name
    self.age = age
    self.gender = gender
    self.job = job

# 引数が多くなりインスタンス変数の設定が増えると管理や可視性の面で難しい。
```

### `@dataclass`を用いた書き方
```py
from dataclasses import dataclass

@dataclass
class Use():
  name: str
  age: int
  gender: str
  job: str

# スッキリ書けて見やすい。
```
## デフォルト値の設定
```py
from dataclasses import dataclass

@dataclass
class Use():
  name: str
  gender: str
  job: str
  age: int = 20 # デフォルト値を設定する場合は最後に持ってくる。

use = Use('suzuki','woman','sales')
print(use.name)
print(use.age)
print(use.gender)
print(use.job)
```

- `flozen = true`を用いて値を変更できないようにイミュータブルに設定する。
  - `dataclasses.FrozenInstanceError: cannot assign to field 'name'`のエラーになる。
```py
from dataclasses import dataclass

@dataclass(frozen=True)
class Use(object):
  name: str
  gender: str
  job: str
  age: int = 20 # デフォルト値を設定する場合は最後に持ってくる。

use = Use('suzuki','woman','sales')
print(use.name)
use.name = 'tanaka'
print(use.age)
print(use.gender)
print(use.job)
```

## ミュータブルなデフォルト値
```py
from dataclasses import dataclass,field

@dataclass
class Use:
    name: str
    gender: str
    job: str
    age: int = 20
    items: list[int] = field(default_factory=list)
    items_list_default: list[int] = field(default_factory=lambda: [1,2,3])
    items_set_default: set[int] = field(default_factory=lambda: {1,2,3})
    items_tuple_default: tuple[int, ...] = field(default_factory=lambda: (1,2,3))
    items_dict_default: dict[str, str] = field(default_factory=lambda: {"key":"1"})

use = Use('suzuki','woman','sales')
print(use.name)
print(use.age)
print(use.gender)
print(use.job)
print(use.items)
print(use.items_list_default)
print(use.items_set_default)
print(use.items_tuple_default)
print(use.items_dict_default)


# suzuki
# 20
# woman
# sales
# []
# [1, 2, 3]
# {1, 2, 3}
# (1, 2, 3)
# {'key': '1'}

```

## オブジェクトのbool値
- 通常のClass
  - 同じ値を持ったインスタンスでも`False`になる。

```py
class User(object):
  def __init__(self,name,age):
    self.name = name
    self.age = age

user1 = User('suzuki',20)
user2 = User('tanaka',30)
print(user1 == user2) # False
```

- dataclassの場合
  - 同じ値を持つインスタンス同士は`True`になる。

```py
from dataclasses import dataclass

@dataclass
class User(object):
  name: str
  age: int

user1 = User('suzuki',20)
user2 = User('suzuki',20)
print(user1 == user2) # True
```

## データクラスのフィールドを辞書型へ変換
```py
from dataclasses import dataclass,asdict

@dataclass(frozen=True)
class User(object):
  name: str
  age: int

user = User('suzuki',20)
result = asdict(user)
print(result)

```

## 参考
https://docs.python.org/ja/3/library/dataclasses.html
https://qiita.com/ttyszk/items/01934dc42cbd4f6665d2
https://zenn.dev/karaage0703/articles/3508b20ece17d4
https://zenn.dev/kumamoto/articles/d0fb1208c47365
