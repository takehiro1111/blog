---
title: "[Python]Classの基礎文法についてまとめてみた"
emoji: "😊"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["python"]
published: true
---
![](/images/py_logo/python-logo-master-v3-TM.png)

## Classの概念
- [公式ドキュメント](https://docs.python.org/ja/3/tutorial/classes.html)の記載
> クラスはデータと機能を組み合わせる方法を提供します。 新規にクラスを作成することで、新しいオブジェクトの 型 を作成し、その型を持つ新しい インスタンス が作れます。 クラスのそれぞれのインスタンスは自身の状態を保持する属性を持てます。 クラスのインスタンスは、その状態を変更するための (そのクラスが定義する) メソッドも持てます。

### 要約
- データ(属性)と、それを操作するための機能(メソッド)をひとまとまりにした「設計図」みたいなもの。
  - その設計図をもとにいくつでもインスタンス(実体)を作れ、各インスタンスは自分用の属性と、それを操作するメソッドを持つ。

## Classを形成するコンポーネント

- オブジェクトの定義対象（クラスとインスタンスは別概念と定義している。）
  - クラス(設計図)
    - オブジェクト指向プログラミングにおける「型」の設計図。
    - ここで定義された内容を元にインスタンスが作られる。

  - インスタンス(生成物)
    - クラスから生成された具体的な実体。  
    - クラスはあくまで型の定義で、インスタンスはそこから生まれる個別のオブジェクト。

- データ(状態)に関する要素
  - 属性(attribute)
    - クラスやインスタンスに結びついたデータ全般を指す総称。
    - クラス変数やインスタンス変数など、オブジェクトに属する値は全て広義には属性と呼べる。
    - 単なる値という点がプロパティとは異なる。

    - クラス変数
      - クラスに属する変数で、全インスタンスで共有される。クラス自体が持つ属性データ。

    - インスタンス変数
      - 各インスタンスごとに保持される変数で、インスタンスごとの固有の値を持つ。

- 振る舞い(機能)に関する要素
  - メソッド
    - クラス内部で定義された関数で、インスタンスやクラスが実行できる動作(振る舞い)を定義する。
    - `self`を受け取るインスタンスメソッドや、`@classmethod`、`@staticmethod`などで定義されるクラスメソッド・静的メソッドもここに含まれる。

  - プロパティ (`@property`)
    - 属性へのアクセス時に、メソッドを通じて動作する仕組み。
    - 見た目は属性と同じように使えるが、実際はメソッドの呼び出しであり、値の取得・設定時に追加処理を挟むことができる。
    - アクセス時に裏で関数(メソッド)が動くという点が属性とは異なる。


### コード上での各コンポーネントの振る舞い
```py
class MyClass(object):
    # クラス変数: クラスに属し、全インスタンスで共有される属性
    class_var = 100

    def __init__(self, x):
        # インスタンス変数: 各インスタンス固有の値
        self.x = x  # これがインスタンス変数 (属性の一種)
        
        # 属性(attribute): class_var, xは共に属性
        # class_varはクラス変数、xはインスタンス変数としてそれぞれが属性として存在する。

    # メソッド: インスタンスやクラスが実行できる関数
    def double(self):
        return self.x * 2

    # プロパティ: 実際はメソッドだが、属性のようにアクセスできる
    @property
    def triple(self):
        # 属性xの値を用いて計算するが、アクセス時にメソッドが呼ばれる
        return self.x * 3


# ----- 実行 -----
# クラスは「型の設計図」
print(MyClass)  # <class '__main__.MyClass'> などと表示される

# インスタンス: クラスから生成される具体的な実体
obj1 = MyClass(10) # (インスタンス変数)
obj2 = MyClass(20) # (インスタンス変数)

# インスタンス変数 (obj1.x, obj2.x) は各インスタンスごとに固有の値
print(obj1.x)  # 10
print(obj2.x)  # 20

# クラス変数 (MyClass.class_var) はクラスに属し、全インスタンスで共有
print(MyClass.class_var)  # 100
print(obj1.class_var)     # 100 (インスタンスからでもアクセス可、同じ値)
print(obj2.class_var)     # 100

# メソッド (obj1.double()) はインスタンス固有のデータ(x)を操作する機能
print(obj1.double())  # 20  (x=10の2倍)
print(obj2.double())  # 40  (x=20の2倍)

# プロパティ (obj1.triple) は属性のようなアクセスだが、裏ではメソッドが呼ばれる
# obj1.tripleは「obj1.x * 3」を返すが、実際は@propertyで定義されたメソッド
print(obj1.triple)  # 30  (x=10の3倍)
print(obj2.triple)  # 60  (x=20の3倍)

# 属性（attribute）について:
#  - class_varやxのように単なる値を保持するものは「属性」
#   - tripleは見た目は属性だが実はプロパティで、アクセス時に計算が行われる
```
## インスタンスを作成する際の処理
- クラスの継承  
  - インスタンス変数のオーバーライド
    - 親クラスのメソッドを使用したい場合
```py:インスタンス変数のオーバーライド
class Parentclass(object):
  def __init__(self,name):
    self.name = name

  def parent_method(self):
    print('親クラスのメソッド')

class Childclass(Parentclass):
  # オーバーライド（parent_methodを子クラスで再定義）
  def parent_method(self):
      print('子クラスでオーバーライドしたメソッド')

  def child_method(self):
    print('子クラスのメソッド')


# 親クラスのインスタンス化
parent_instance = Parentclass('parent_name')
parent_instance.parent_method()  # "親クラスのメソッド"

# 子クラスのインスタンス化（継承されているので、親クラスの__init__を利用）
child_instance = Childclass('child_name')
child_instance.parent_method()   # "子クラスでオーバーライドしたメソッド"
child_instance.child_method()    # "子クラス独自のメソッド"
```

```py:親クラスで定義したインスタンス変数を子クラスでも使用する場合
class Parentclass(object):
  def __init__(self,name):
    self.name = name

  def parent_method(self):
    print(f'親クラスのメソッド:{self.name}')

class Childclass(Parentclass):
  def __init__(self,name):
    super().__init__(name) # 親クラスの__init__を呼び出し、self.nameを初期化

  def child_method(self):
    print(f'子クラスのメソッド:{self.name}')

# super() が親メソッドを呼び出していることが分かる。
child_instance = Childclass('child_name') 
child_instance.parent_method()

# 親クラスのメソッド:child_name
# 親クラスのメソッドを呼び出しています。
```

## デコレーター
- デコレータには既存の関数に機能を追加する働き
  - 関数を修飾して大元の関数の引数にすることができる。
```py
def my_decorator(func):
    def wrapper(*args, **kwargs):
        print("関数実行前の処理")
        result = func(*args, **kwargs)
        print("関数実行後の処理")
        return result
    return wrapper

@my_decorator  # execute_instance = my_decorator(test_function) と同等
def execute_instance():
    print("fuction execute")

# 実行
execute_instance()

# 関数実行前の処理
# fuction execute
# 関数実行後の処理
```

### classmethodとstaticmethod
- クラス内で定義するが、インスタンスに依存しない処理を行いたいときに利用するデコレータ。

#### @classmethod
- 第一引数にクラスオブジェクト(cls)を受け取るメソッド。
- クラス変数やクラスメソッドを使った処理、または代替コンストラクタ的な使い方に向いている。
- インスタンスが無くても、clsを通じてクラスレベルの情報にアクセスできる。
```py
class MyClass:
    class_var = 100

    @classmethod
    def show_class_var(cls):
        print(cls.class_var)

cs = MyClass
cs.show_class_var() # 100
```

#### @staticmethod
- 引数に`self`や`cls`を取らず、クラスやインスタンスには一切依存しない純粋な関数として振る舞う。（クラス名で呼び出せるただの関数的なイメージ）
- 機能的にはクラスの名前空間に置かれた通常の関数と同様だが、クラスに関連した処理を論理的にまとめるために使われる。

```py
class Person(object):
  def __init__(self):
    self.t = 30

  @staticmethod
  def birthday(year):
    print('私の誕生日は{}です。'.format(year))

Person.birthday('3月')
```



## セッターとゲッター
- 変数に`_`や`__`がついていると慣習的に外部から操作しないよう明示的に設定されている。
  - `_`の場合->変更自体は可能
  - `__`の場合->名前マングリングによって外部アクセスは不可。

- `@property`と`@<property名>.setter`を使うことで、属性（インスタンス変数）へのアクセスや代入を制御できる。
```py
class Person:
    def __init__(self, name, age):
        self._name = name        # アンダースコアで「外部から触るな」という慣習的メッセージ
        self.__age = age         # ダブルアンダースコアで名前マングリングされ、外部アクセスが難しくなる

    @property
    def name(self):
        # ゲッター: _nameを安全に返す
        return self._name

    @name.setter
    def name(self, new_name):
        # セッター: 条件に該当する場合は呼び出せる。
        if not new_name:
            raise ValueError("名前は空にできない")
        self._name = new_name

    @property
    def age(self):
        # ゲッター: __ageを安全に返す
        return self.__age

    # ageに対してセッターを定義しないことで外部からageを変更できなくなる
    # @age.setter
    # def age(self, new_age):
    #     if new_age < 0:
    #         raise ValueError("年齢は0以上である必要がある")
    #     self.__age = new_age


p = Person("Alice", 30)
print(p.name)  # "Alice"
p.name = "Bob"  # セッターを通して名前を変更
print(p.name)  # "Bob"

print(p.age)  # 30
# p.age = 40  # セッターが無いため直接代入はエラーになる

# _nameは慣習上触るべきでないが、実際にはアクセスできる
p._name = "Charlie"
print(p.name)  # "Charlie" (本来はやらない方が良い)

# __ageは名前マングリングにより直接アクセスが難しい
# print(p.__age)  # AttributeError
# ただし、Person._Person__ageのように名前マングリング先を知ればアクセスできるので絶対的な保護ではない。

print(Person.__dict__)  # クラスの名前空間を見ると__ageが_Person__ageとして格納されている
```
## 参考
https://docs.python.org/ja/3/tutorial/clas
https://www.sejuku.net/blog/28182
https://codelikes.com/python-class-inheritance/
https://qiita.com/Fendo181/items/a934e4f94021115efb2e
https://www.sejuku.net/blog/25130
https://helve-blog.com/posts/python/python-staticmethod-classmethod/
