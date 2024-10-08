---
title: "[Python]ジェネレーターの概念、挙動"
emoji: "👻"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: []
published: true
---
![](/images/py_logo/python-logo-master-v3-TM.png)
## 1.ジェネレーターとは？
- Pythonでイテレーター(`次のデータの要素を逐次返すオブジェクト`)を簡単に作成するための関数。
- 通常の関数と異なり、`return`の代わりに`yield`を使って値を返す。
- 一度に全ての値をメモリに保持するのではなく、必要に応じて1つずつ値を生成するため、メモリ効率が良い。
&nbsp;

## 2.ジェネレーターを使用するメリット、デメリット
### メリット
- メモリ効率の向上
  - 遅延評価を利用しており、データが必要になるまでその生成や処理を遅らせることで、逐次処理が可能になる。
    - ジェネレーターを使用しない場合は、リストが一度に全てのメモリを占有するため、特に大量のデータを扱う場合にメモリの負荷が高くなる。
    - ジェネレーター使用時は、1つの値を生成したら次の値を生成するため、メモリに全ての値を一度に保持する必要がない。
    特に大量のデータを扱う場合や無限に続くようなデータを扱う場合でもメモリの効率が非常に良い。

- コード可読性の向上
  - `yield`を用いることで、以下の例だとリストを作成する手間を省けて処理の流れがシンプルになる。
  それに伴い、コード量が減り可読性が上がる。

- 無限シーケンスのサポート
  - 本記事の事例では用いていないが、無限に続くようなデータ列を自然に処理できる。
    - 以下コードで`range(n)`のような場合

### デメリット
- 処理が単発のため、再利用ができない。
  - 逐次処理で一度処理を抜けると、リスト等のような一括で処理するデータ型と比べて再利用ができない。
  新しいジェネレーターを再生成すれば対応出来るが、それに伴うオーバーヘッドを考慮する必要がある。

- 全体のサイズや長さがわかりにくい
  - ジェネレーターを用いるとどの程度の処理を行うのか判別しにくい。

&nbsp;
## 3.コード
### ジェネレーターを使用しない場合

```py
def create_num_list():
    result = []
    for i in range(1,11):
        result.append(i)
    return result

# リストを作成して、各要素を処理する
for num in create_num_list():
  print(num)
```

```shell:result
1
2
3
4
5
6
7
8
9
10

```

### ジェネレーター使用時
```py
def create_generator():
    for i in range(1,11):
        yield i

# ジェネレーターを使って各要素を順次処理する
for num in create_generator():
    print(num)
```

```shell:result
1
2
3
4
5
6
7
8
9
10
```

- 以下ではnext関数を用いて逐次処理のイメージが湧きやすいように書いている。
  - リストだと要素が一括で処理されるが、ジェネレーターを用いることで必要な分のみ処理をすることも可能。

```py
def create_generator():
  for i in range(1,11):
    yield i

gen = create_generator()
print(next(gen))
print(next(gen))
print(next(gen))
print(next(gen))
print(next(gen))
```

```shell:result
1
2
3
4
5
```

### ジェネレーター式
- 以下のような書き方でも同じ結果を得られる。
  - リスト内包表記の`[]`を`()`に置き換えることで、簡潔にジェネレーターを作成できる。
  - 通常のジェネレーターと同様、forループなどで逐次的に値を取り出すことができる。
  - コードをより短く簡潔に書くことができ、可読性が向上する。
```py
# ジェネレーター式を使用して1から5までの数を生成
gen = (i for i in range(1, 11))

for num in gen:
  print(num)
```

```shell:result
1
2
3
4
5
6
7
8
9
10
```

### 例外処理でのジェネレーターの使用例
- generate_numbersがyieldで値を返すが、`num == 3`のときに関数の外部から意図的に`ValueError`を発生させるという処理も可能。

```py
def generate_numbers():
    try:
        for i in range(1, 6):
            yield i
    except Exception as e:
        print(f"例外が発生: {e}")

gen = generate_numbers()

# 意図的に例外を発生させる
try:
    for num in gen:
        if num == 3:
            raise ValueError("意図的な例外")
        print(num)
except Exception as e:
    print(f"外部で例外をキャッチ: {e}")

```

```shell:result
1
2
外部で例外をキャッチ: 意図的な例外
```
