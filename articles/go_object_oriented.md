---
title: "Go言語におけるオブジェクト指向の実装(classベースとの違い)"
emoji: "📝"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Go", "オブジェクト指向"]
published: true
---
![](/images/go/go_logo.png =450x)

## 1.読者想定
- Goの初学者レベル(私含め)
  - Goとclassを用いたオブジェクト指向の実装をする他言語と書き方を比較整理したい方。

:::message
- 思考の整理のために本記事を書いていますので、独特な表現がある場合はあまり気にしないでください。
- コードベースでの整理をしたいため、オブジェクト志向についての言及はしておりません。
- Python,TypeScriptとの比較は私自身のスキルセットの影響のため、比較する際の言語選定に深い意味はないです。
:::

&nbsp;
## 2.classで書く場合
- classがデータ（property）と振る舞い（method）をカプセル化し、継承によってコードの再利用性を高めます。

### Pythonの場合
```py
class Dog:
    def __init__(self, name):
        self.name = name

    def speak(self):
        print(f"{self.name} says Woof!")

class Cat:
    def __init__(self, name):
        self.name = name

    def speak(self):
        print(f"{self.name} says Meow!")

# 共通の処理を行う関数
def say_something(animal):
    animal.speak()

my_dog = Dog("Buddy")
my_cat = Cat("Whiskers")

say_something(my_dog)
say_something(my_cat)
```

```shell
python main.py

Buddy says Woof!
Whiskers says Meow!
```

### TypeScriptの場合
```ts
interface Speaker {
    speak(): void;
}

class Dog implements Speaker {
    name: string;

    constructor(name: string) {
        this.name = name;
    }

    speak(): void {
        console.log(`${this.name} says Woof!`);
    }
}

class Cat implements Speaker {
    name: string;

    constructor(name: string) {
        this.name = name;
    }

    speak(): void {
        console.log(`${this.name} says Meow!`);
    }
}

// 共通の処理を行う関数
function saySomething(animal: Speaker): void {
    animal.speak();
}

const myDog = new Dog("Buddy");
const myCat = new Cat("Whiskers");

saySomething(myDog);
saySomething(myCat);

```
```shell
tsc main.ts
node main.js

Buddy says Woof!
Whiskers says Meow!
```
&nbsp;
&nbsp;

## 3.Goで書く場合
Goにはクラスがありません。代わりに以下の要素を組み合わせてオブジェクト指向的な設計を行います。

### 3-1.構成要素
```md
## 1.struct (構造体)
  - データ（フィールド）をまとめる型です。PythonやTypeScriptのクラスにおける属性のようなものです。
## 2.メソッド
  - structに関連付けられた関数です。クラスのメソッドと同様に、そのstructのデータに対して操作を行います。
## 3.interface (インターフェース)
  - メソッドのシグネチャ（定義）の集合です。振る舞いを定義し、特定の振る舞いを持つstructがそのinterfaceを満たすことを保証します。
## 4.ダックタイピング
  - Goのインターフェースは暗黙的に満たされます。  interfaceに定義されたすべてのメソッドをstructが持っていれば、そのstructは自動的にそのinterfaceを満たします
```
&nbsp;
### 3-2.構造体のみの場合とinterfaceを含める際の実装の比較
```md
### structのみの場合
- 個々のデータとそれに特化した振る舞いをカプセル化します。
- 各structが独立した機能を提供するため、異なる型間で共通の処理を行うには個別のコードが必要です。

### interface,ダッグタイピングの概念を用いた場合
- 共通の振る舞いを定義し、その振る舞いを持つstructは自動的にそのinterfaceとして扱われます（ダックタイピング）。
- Goは`具体的な型に依存しない汎用的な処理（ポリモーフィズム）`を実現し、コードの柔軟性と拡張性を高めます。
```

&nbsp;
### 例1.structによるデータの定義とメソッドの追加
- `Dog`と`Cat`はそれぞれ独立したstructです。
- `func (d Dog) Bark()` のように、関数名の前にstructのインスタンスを(値)レシーバーとして指定することで、そのstructのメソッドとして定義されます。
```go
package main

import "fmt"

// Dog structは名前を持つ
type Dog struct {
  Name string
}

// DogにBarkメソッドを追加
func (d Dog) Bark() {
  fmt.Printf("%s says Woof!\n", d.Name)
}

// Cat structは名前を持つ
type Cat struct {
  Name string
}

// CatにMeowメソッドを追加
func (c Cat) Meow() {
  fmt.Printf("%s says Meow!\n", c.Name)
}

func main() {
  myDog := Dog{Name: "Buddy"}
  myDog.Bark()

  myCat := Cat{Name: "Whiskers"}
  myCat.Meow()
}
```


```shell
go run main.go

Buddy says Woof!
Whiskers says Meow!

```

&nbsp;
### 例2.interfaceによる振る舞いの定義とダックタイピング
- `Speaker`インターフェースは`Speak()`メソッドの存在を定義しています。

- DogとCatは、`Speak()`メソッドをそれぞれ実装しているため、明示的に宣言しなくても`Speaker`インターフェースを暗黙的に満たします。これがGoのダックタイピングです。
  - `もしそれがアヒルのように歩き、アヒルのように鳴くのなら、それはアヒルである`というGoの思想です。

- `SaySomething`関数は`Speaker`インターフェースを受け取るため、`Dog`型と`Cat`型のどちらのインスタンスも渡すことができます。これにより、異なる型に対して共通の処理を行うことができます。

```go
package main

import "fmt"

// Speaker interfaceはSpeakメソッドを持つことを要求する
type Speaker interface {
    Speak()
}

// Dog structは名前を持つ
type Dog struct {
    Name string
}

// Cat structは名前を持つ
type Cat struct {
    Name string
}

// DogがSpeakerインターフェースを満たすようにSpeakメソッドを実装
func (d Dog) Speak() {
    fmt.Printf("%s says Woof!\n", d.Name)
}

// CatがSpeakerインターフェースを満たすようにSpeakメソッドを実装
func (c Cat) Speak() {
    fmt.Printf("%s says Meow!\n", c.Name)
}

// SaySomething関数はSpeakerインターフェースを引数にとる
// これにより、Speakメソッドを持つ任意の型を受け入れられる
func SaySomething(s Speaker) {
    s.Speak()
}

func main() {
    myDog := Dog{Name: "Buddy"}
    myCat := Cat{Name: "Whiskers"}

    SaySomething(myDog) // DogはSpeakerインターフェースを満たす
    SaySomething(myCat) // CatはSpeakerインターフェースを満たす
}
```

```shell
go run main.go

Buddy says Woof!
Whiskers says Meow!

```

## 4.感想
- classを用いた書き方の方が直感的だなと思いました。（多分、慣れですね。。）
