---
title: "Pthonの例外処理"
emoji: "✨"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: [Python]
published: true
---

![](/images/py_logo/python-logo-master-v3-TM.png)

## 0.例外処理とは？
プログラム実行中にエラー(例外)が発生する際、エラーになった場合の処理を予め設定し実行すること。
通常はエラーが発生するとその時点でプログラムが停止するが、例外処理を定義しておくことで
エラーの原因をログに記録したり、エラーメッセージを表示したり、プログラムの一部だけを再実行出来たり等の対応が可能になる。


## 1.基本的な例外処理
```py
def add_num(a,b):
  return a + b

try:
  r = add_num(2,"3")
except Exception as e: # 例外(エラー)が発生した時の処理を書く
  print(e)
  print('例外処理が発生した。')
else: # 例外が発生しない場合の処理を書く
  print(r)
finally: # 例外が発生するかどうかに関わらず実行したい処理を書く
  print('処理の終了')

```
- 実行結果
![](/images/py_exception_handling/exception_handling_1.png)

## 2.独自の例外処理を定義
```py
# 独自例外の処理
class MycaseError(Exception):
  pass

def mycase():
  fruits = ['APPLE','banana','orange']
  for fruit in fruits:
    if fruit.isupper(): # リストの各要素が全て大文字の場合
      raise MycaseError(f'{fruit}が大文字になっているためのエラーです。') # クラスで継承しているMycaseError処理が発生

try:
  mycase()
except MycaseError as e:
  print(e) # raiseで定義しているエラーメッセージの表示
  print('例外処理の発生')
else:
  print('例外処理は発生しなかった')
finally:
  print('必ず表示される')
```
- 実行結果
![](/images/py_exception_handling/exception_handling_2.png)
