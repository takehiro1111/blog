---
title: "[Python]各データ型のメソッドを整理"
emoji: "🤖"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["python"]
published: true
---

![](/images/py_logo/python-logo-master-v3-TM.png)

## 1.List
### 特徴
- 順序があり、変更可能（ミュータブル）。
- 重複要素もOKで、インデックスで要素にアクセスできる

### メソッド一覧
```py
print(dir(list))

['__add__', '__class__', '__class_getitem__', '__contains__', '__delattr__', '__delitem__', '__dir__', '__doc__', '__eq__', '__format__', '__ge__', '__getattribute__', '__getitem__', '__getstate__', '__gt__', '__hash__', '__iadd__', '__imul__', '__init__', '__init_subclass__', '__iter__', '__le__', '__len__', '__lt__', '__mul__', '__ne__', '__new__', '__reduce__', '__reduce_ex__', '__repr__', '__reversed__', '__rmul__', '__setattr__', '__setitem__', '__sizeof__', '__str__', '__subclasshook__', 'append', 'clear', 'copy', 'count', 'extend', 'index', 'insert', 'pop', 'remove', 'reverse', 'sort']
```

| メソッド | 意味 | 
| ---- | ---- |
| append() | 末尾に要素を追加。 |
| extend() | リストに別のリストやタプルを結合できる。 |
| insert() | 指定したインデックスに要素を追加 |
| clear() | リストの全要素を削除する |
| copy() | 要素をコピーする（オブジェクト自体は別物） |
| count() | 指定した要素がいくつ存在するか表示する |
| index() | 指定した要素のインデックス番号を取得する|
| pop() | 指定インデックスの要素を削除して返す。デフォルトは末尾 |
| reverse() | 要素を逆順に並び替える |
| sort(key=None, reverse=False) | リストの要素を並び替える |

### 使用例
```py
a = [1, 2, 3]
a.append(4)  # [1, 2, 3, 4]

a = [1, 2, 3]
a.clear()  # []

a = [1, 2, 3]
b = a.copy()  # bは[1, 2, 3]、aとbは別オブジェクト

a = [1, 2, 2, 3]
a.count(2)  # 2

a = [1, 2]
a.extend([3, 4])  # [1, 2, 3, 4]

a = [10, 20, 30]
a.index(20)  # 1

a = [1, 3]
a.insert(1, 2)  # [1, 2, 3]

a = [1, 2, 3]
val = a.pop()  # valは3, aは[1, 2]

a = [1, 2, 2, 3]
a.remove(2)  # [1, 2, 3]

a = [1, 2, 3]
a.reverse()  # [3, 2, 1]

a = [3, 1, 2]
a.sort()  # [1, 2, 3]
a.sort(reverse=True)  # [3, 2, 1]
```

## 2.tuple
### 特徴
- 順序があり、変更不可（イミュータブル）。
   - tupleはイミュータブル(不変)なシーケンスのため、listのように多様なメソッドを持ち合わせていない。
- 重複要素もOKで、インデックスで要素にアクセス可能。

### メソッド一覧
```py
print(dir(tuple))

['__add__', '__class__', '__class_getitem__', '__contains__', '__delattr__', '__dir__', '__doc__', '__eq__', '__format__', '__ge__', '__getattribute__', '__getitem__', '__getnewargs__', '__getstate__', '__gt__', '__hash__', '__init__', '__init_subclass__', '__iter__', '__le__', '__len__', '__lt__', '__mul__', '__ne__', '__new__', '__reduce__', '__reduce_ex__', '__repr__', '__rmul__', '__setattr__', '__sizeof__', '__str__', '__subclasshook__', 'count', 'index']
```

| メソッド | 意味 | 
| ---- | ---- |
| count() | 末尾に要素を追加。 |
| index() | リストに別のリストやタプルを結合できる。 |

```py
t = (1, 2, 2, 3)

print(t.count(2))  # 2
print(t.index(2))  # 1
```
## 3.dict
### 特徴
- キーと値のペアで管理するマッピング型。
- キーは重複不可で、値は何でもOK。
- Python 3.7以降は挿入順を保持するが、基本はキーでアクセス。
- 変更可能。
- `dir`関数を用た使用可能なメソッドの表示
  - キーバリューの取り出しはよく使用するので押さえておきたい。

### メソッド一覧
```py
print(dir(dict))

['__class__', '__class_getitem__', '__contains__', '__delattr__', '__delitem__', '__dir__', '__doc__', '__eq__', '__format__', '__ge__', '__getattribute__', '__getitem__', '__getstate__', '__gt__', '__hash__', '__init__', '__init_subclass__', '__ior__', '__iter__', '__le__', '__len__', '__lt__', '__ne__', '__new__', '__or__', '__reduce__', '__reduce_ex__', '__repr__', '__reversed__', '__ror__', '__setattr__', '__setitem__', '__sizeof__', '__str__', '__subclasshook__', 'clear', 'copy', 'fromkeys', 'get', 'items', 'keys', 'pop', 'popitem', 'setdefault', 'update', 'values']
```

| メソッド | 意味 | 
| ---- | ---- |
| get(key, default=None) | キーを指定して値を取得する。 |
| items() | (キー, 値)のタプルを要素として返す。 |
| keys() | 辞書の全てのキーを返す。 |
| values() | 辞書の全てのバリューを返す。 |
| fromkeys(iterable, value=None) | イテラブル内の要素をキーとして、新しい辞書を作成するクラスメソッド |
| copy() | 要素をコピーする（オブジェクト自体は別物） |
| clear() | 全てのキーと値のペアを削除する |
| pop(key, default=None) | 指定キーの値を取り出して削除する。キーが無い場合はdefaultを返す。 |
| popitem() | 辞書から最後に挿入されたキーと値のペアを取り出して削除する|
| setdefault(key, default=None) | 指定キーが無ければdefaultで登録し、その値を返す。キーがあれば既存値を返す |
| update(other) | 他の辞書やキー/値のペアから辞書を更新する |

### 使用例
```py
d = {"a": 1}
print(d.get("a"))    # 1
print(d.get("b", 0)) # 0

d = {"a": 1, "b": 2}
print(d.items())  # dict_items([("a",1),("b",2)])

d = {"a": 1, "b": 2}
print(d.keys())  # dict_keys(["a", "b"])

d = {"a": 1, "b": 2}
print(d.values())  # dict_values([1, 2])

keys = ["x", "y"]
d = dict.fromkeys(keys, 0)  # {"x": 0, "y": 0}

d = {"a": 1, "b": 2}
new_d = d.copy()  # new_dは{"a": 1, "b": 2}

d = {"a": 1, "b": 2}
d.clear()  # dは{}

d = {"a": 1, "b": 2}
val = d.pop("a")   # valは1, dは{"b": 2}

d = {"a": 1, "b": 2}
key_val = d.popitem()  # ("b", 2)を返し、dは{"a": 1}に

d = {"a": 1}
print(d.setdefault("a", 0))  # 1
print(d.setdefault("b", 2))  # 2 (新規追加)

d = {"a": 1}
d.update({"b": 2, "c": 3})  # dは{"a":1, "b":2, "c":3}
```
## 4.set
### 特徴
- 順序なし、重複なしの集合型。
- 変更可能。
- 要素の存在判定が高速で、インデックスでの直接アクセスは不可。

### メソッド一覧
```py
print(dir(set))

 ['__and__', '__class__', '__class_getitem__', '__contains__', '__delattr__', '__dir__', '__doc__', '__eq__', '__format__', '__ge__', '__getattribute__', '__getstate__', '__gt__', '__hash__', '__iand__', '__init__', '__init_subclass__', '__ior__', '__isub__', '__iter__', '__ixor__', '__le__', '__len__', '__lt__', '__ne__', '__new__', '__or__', '__rand__', '__reduce__', '__reduce_ex__', '__repr__', '__ror__', '__rsub__', '__rxor__', '__setattr__', '__sizeof__', '__str__', '__sub__', '__subclasshook__', '__xor__', 'add', 'clear', 'copy', 'difference', 'difference_update', 'discard', 'intersection', 'intersection_update', 'isdisjoint', 'issubset', 'issuperset', 'pop', 'remove', 'symmetric_difference', 'symmetric_difference_update', 'union', 'update']
```

| メソッド | 意味 | 
| ---- | ---- |
| add() | 要素を追加する。 |
| copy() | コピーを返す。 |
| clear() | 全ての要素を削除する。 |
| discard() | 指定要素を削除する。(要素が無くてもエラーは出ない) |
| remove() | 指定要素を削除する。(要素が無い場合は`KeyError`となる。) |
| pop() | 任意の要素を削除して返す(どの要素が出るかは保証なし) |
| update() | 他の集合やイテラブルの要素を追加する |
| union() | 和集合を返す(演算子|でも可) |
| intersection(other) | 積集合を返す(演算子&でも可) |
| difference(other) | 差集合を返す(演算子-でも可) |
| symmetric_difference(other) | 対称差集合を返す(演算子^でも可) |
| issubset(other) | 自集合がotherの部分集合ならTrue |
| issuperset(other) | 自集合がotherを包含していればTrue |
| isdisjoint(other) | 自集合とotherが共通要素を持たない場合はTrue |

### 使用例
```py
s = {1, 2}
s.add(3)  # sは{1, 2, 3}

s = {1, 2, 3}
s.clear()  # sは空集合 set()

s = {1, 2, 3}
new_s = s.copy()  # new_sは{1,2,3}

s = {1, 2, 3}
s.discard(2)  # sは{1, 3}
s.discard(4)  # sは変わらず{1,3}

s = {1, 2, 3}
s.remove(3)  # sは{1,2}
# s.remove(4) はエラー

s = {1, 2, 3}
val = s.pop()  # 1,2,3のいずれかを削除して返す

s = {1, 2}
s.update({2, 3, 4})  # sは{1, 2, 3, 4}

s1 = {1, 2}
s2 = {2, 3}
s3 = s1.union(s2)  # {1, 2, 3}

s1 = {1, 2}
s2 = {2, 3}
s3 = s1.intersection(s2)  # {2}

s1 = {1, 2, 3}
s2 = {2, 4}
s3 = s1.difference(s2)  # {1, 3}

s1 = {1, 2, 3}
s2 = {2, 3, 4}
s3 = s1.symmetric_difference(s2)  # {1, 4}

s1 = {1, 2}
s2 = {1, 2, 3}
print(s1.issubset(s2))  # True

s1 = {1, 2, 3}
s2 = {1, 2}
print(s1.issuperset(s2))  # True

s1 = {1, 2}
s2 = {3, 4}
print(s1.isdisjoint(s2))  # True
```

## 5.flozenset
### 特徴
- setと同じで重複を許容しないデータ型だが、イミュータブルであることがsetとの違い。


### メソッド一覧
```py
print(dir(frozenset))

['__and__', '__class__', '__class_getitem__', '__contains__', '__delattr__', '__dir__', '__doc__', '__eq__', '__format__', '__ge__', '__getattribute__', '__getstate__', '__gt__', '__hash__', '__init__', '__init_subclass__', '__iter__', '__le__', '__len__', '__lt__', '__ne__', '__new__', '__or__', '__rand__', '__reduce__', '__reduce_ex__', '__repr__', '__ror__', '__rsub__', '__rxor__', '__setattr__', '__sizeof__', '__str__', '__sub__', '__subclasshook__', '__xor__', 'copy', 'difference', 'intersection', 'isdisjoint', 'issubset', 'issuperset', 'symmetric_difference', 'union']
```

| メソッド | 意味 | 
| ---- | ---- |
| copy() |  同一要素を持つfrozensetのコピーを返す |
| union() | 和集合を返す(演算子|でも可) |
| intersection(other) | 積集合を返す(演算子&でも可) |
| difference(other) | 差集合を返す(演算子-でも可) |
| symmetric_difference(other) | 対称差集合を返す(演算子^でも可) |
| issubset(other) | 自集合がotherの部分集合ならTrue |
| issuperset(other) | 自集合がotherを包含していればTrue |
| isdisjoint(other) | 自集合とotherが共通要素を持たない場合はTrue |

### 使用例
```py
fs = frozenset([1, 2, 3])
new_fs = fs.copy()  # frozenset({1,2,3})

fs1 = frozenset([1, 2, 3])
fs2 = frozenset([2, 4])
fs3 = fs1.difference(fs2)  # frozenset({1,3})

fs1 = frozenset([1, 2])
fs2 = frozenset([2, 3])
fs3 = fs1.intersection(fs2)  # frozenset({2})

fs1 = frozenset([1, 2])
fs2 = frozenset([3, 4])
print(fs1.isdisjoint(fs2))  # True

fs1 = frozenset([1, 2])
fs2 = frozenset([1, 2, 3])
print(fs1.issubset(fs2))  # True

fs1 = frozenset([1, 2, 3])
fs2 = frozenset([1, 2])
print(fs1.issuperset(fs2))  # True

fs1 = frozenset([1, 2, 3])
fs2 = frozenset([2, 3, 4])
fs3 = fs1.symmetric_difference(fs2)  # frozenset({1,4})

fs1 = frozenset([1, 2])
fs2 = frozenset([2, 3])
fs3 = fs1.union(fs2)  # frozenset({1,2,3})
```

## 参考
https://note.nkmk.me/python-list-append-extend-insert/
https://note.nkmk.me/python-list-clear-pop-remove-del/
https://note.nkmk.me/python-list-sort-sorted/
https://www.headboost.jp/python-tuple/
https://www.headboost.jp/python-everything-to-know-about-dict/
https://note.nkmk.me/python-set/
https://www.headboost.jp/python-set/
