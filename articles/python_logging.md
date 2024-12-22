---
title: "[Python]ロギングの基本的な書き方"
emoji: "💬"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["python"]
published: true
---
![](/images/py_logo/python-logo-master-v3-TM.png)

## loggingとは？
- ただ単純に表示させたいならprint文でも良いが、ログを残すのに特化した機能が豊富なライブラリ。
- ドキュメントでは以下のように定義されている。
### [参考](https://docs.python.org/ja/3/howto/logging.html)
> logging は、あるソフトウェアが実行されているときに起こったイベントを追跡するための手段です。ソフトウェアの開発者は、特定のイベントが発生したことを示す logging の呼び出しをコードに加えます。イベントは、メッセージで記述され、これに変数データ (すなわち、イベントが起こる度に異なるかもしれないデータ) を加えることもできます。イベントには、開発者がそのイベントに定めた重要性も含まれます。重要性は、レベル (level) や 重大度 (severity) とも呼ばれます。


## 基本的な使い方
- logの重大度 (severity) 別にメッセージを表示できます。
  - セットしたレベル以上の重大度に該当するログが表示されます。

- カスタマイズする場合
  - 小規模プロジェクトでは、以下のようにbasicConfig を活用するだけでも十分です。
  - 大規模なプロジェクトでは、後述するJSON 設定やカスタムハンドラーを活用することで柔軟性が向上します。

```py
import logging

logging.basicConfig(encoding='utf-8', level=logging.INFO)

logging.critical('crit')
logging.error('error')
logging.warning('warn')
logging.info(f"info:{'tutorial'}")
logging.debug('debug')

# CRITICAL:root:crit
# ERROR:root:error
# WARNING:root:warn
# INFO:root:info:tutorial
```

## フォーマッター
- ログの出力形式を定義します。
  - [ドキュメント](https://docs.python.org/ja/3/library/logging.html#logrecord-attributes)に属性の説明が記載されています。
  - フォーマッターを使うことで、ログの見やすさを改善し、デバッグ効率を向上できます。
```py
import logging

FORMATTER = '%(asctime)s - (%(filename)s) - [%(levelname)s] - %(message)s'
logging.basicConfig(level=logging.INFO,format=FORMATTER)

logging.critical('crit')
logging.error('error')
logging.warning('warn')
logging.info(f'info:{'tutorial'}')
logging.debug('debug')

# 2024-12-22 10:20:45,688 - (test.py) - [CRITICAL] - crit
# 2024-12-22 10:20:45,688 - (test.py) - [ERROR] - error
# 2024-12-22 10:20:45,688 - (test.py) - [WARNING] - warn
# 2024-12-22 10:20:45,688 - (test.py) - [INFO] - info:tutorial

```

## loggingではなく、loggerオブジェクトを使用すべき理由
- モジュール等のコンポーネント単位で柔軟なログ設定が可能になるため。
  - モジュールやクラスごとに独立したロガーを作成することで、コードの再利用性が向上する。
- ハンドラーでログ出力先を定義できる（後述）

```py:main.py
import logging

# create formatter(ログの出力形式)
FORMATTER = '%(asctime)s - (%(filename)s) - [%(levelname)s] - %(message)s'
logging.basicConfig(level=logging.INFO,format=FORMATTER)

# create logger
logger = logging.getLogger(__name__)

logger.debug('ロガーで取得したデバッグログです。')
logger.info('通常の挙動です。')
logger.warning('警告です。')
logger.error('ファイルが見つかりません。')
logger.critical('緊急事態です。')

# 2024-12-22 10:34:38,941 - (main.py) - [INFO] - 通常の挙動です。
# 2024-12-22 10:34:38,941 - (main.py) - [WARNING] - 警告です。
# 2024-12-22 10:34:38,941 - (main.py) - [ERROR] - ファイルが見つかりません。
# 2024-12-22 10:34:38,941 - (main.py) - [CRITICAL] - 緊急事態です。
```

### 他モジュールのログ設定をimportする場合
```py:main.py
import logging
import sub

# create formatter(ログの出力形式)
FORMATTER = '%(asctime)s - (%(filename)s) - [%(levelname)s] - %(message)s'
logging.basicConfig(level=logging.INFO,format=FORMATTER)

# create logger
logger = logging.getLogger(__name__)
logger.info('mainのロガー出力(info)')

# invoke sub module
sub.sub_log_func()

```

```py:sub.py
import logging

# create logger
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

def sub_log_func():
  logger.info('サブファイルのロギング設定です。')
  logger.error('サブファイルのロギング設定のエラーです。')
```

- 出力
```zsh
python main.py

2024-12-22 10:47:13,872 - (main.py) - [INFO] - mainのロガー出力(info)
2024-12-22 10:47:13,872 - (sub.py) - [INFO] - サブファイルのロギング設定です。
2024-12-22 10:47:13,872 - (sub.py) - [ERROR] - サブファイルのロギング設定のエラーです。
```


## ハンドラー
- ログの出力先を制御する設定。
- [ドキュメント](https://docs.python.org/ja/3/howto/logging.html#handlers)の定義
> Handler オブジェクトは適切なログメッセージを (ログメッセージの深刻度に基づいて) ハンドラの指定された出力先に振り分けることに責任を持ちます。 Logger オブジェクトには addHandler() メソッドで 0 個以上のハンドラを追加することができます。

### StreamHandler
- コンソールへ出力(標準出力や標準エラー出力)するハンドラー
```py
import logging

# ロガーを作成
logger = logging.getLogger("example_logger")
logger.setLevel(logging.DEBUG)

# StreamHandler を作成
stream_handler = logging.StreamHandler()  # デフォルトは sys.stderr

# ログフォーマットを設定
formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
stream_handler.setFormatter(formatter)

# ロガーにハンドラーを追加
logger.addHandler(stream_handler)

# ログを出力
logger.debug("This is a debug message")
logger.info("This is an info message")
logger.warning("This is a warning message")

# 2024-12-22 10:59:17,388 - example_logger - DEBUG - This is a debug message
# 2024-12-22 10:59:17,388 - example_logger - INFO - This is an info message
# 2024-12-22 10:59:17,388 - example_logger - WARNING - This is a warning message
```

## FileHandler
- 指定したファイルへログを出力する。
  - 2回目以降の出力では、ファイルへ追記する。
```py
import logging

# create formatter(ログの出力形式)
FORMATTER = '%(asctime)s - (%(filename)s) - [%(levelname)s] - %(message)s'

# カスタムロガーでレベル設定をしており、そちらが優先されて直接影響しないため不要。
# logging.basicConfig(level=logging.INFO)

# create logger
# ロガーの共通設定になるレベルは最も低レベルのDEBUGを定義している。
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

# DEBUGレベルのログを'log/debug_handler.log'へ出力する。
handler = logging.FileHandler(
  'log/debug_handler.log',mode='w'
  )
handler.setLevel(logging.DEBUG)
handler.setFormatter(logging.Formatter(FORMATTER))
logger.addHandler(handler)

# WARNINGレベルのログを'log/warn_handler.log'へ出力する。
warn_handler = logging.FileHandler(
  'log/warn_handler.log',mode='w'
  )
warn_handler.setLevel(logging.WARNING)
warn_handler.setFormatter(logging.Formatter(FORMATTER))
logger.addHandler(warn_handler)

logger.debug('ロガーで取得したデバッグログです。!!!!!!!!!!!!!')
logger.info('通常の挙動です。')
logger.warning('警告です。')
logger.error('ファイルが見つかりません。')
logger.critical('緊急事態です。')

```

### 出力結果
```py:log/debug_handler.log
2024-12-22 11:14:50,354 - (log3.py) - [DEBUG] - ロガーで取得したデバッグログです。!!!!!!!!!!!!!
2024-12-22 11:14:50,354 - (log3.py) - [INFO] - 通常の挙動です。
2024-12-22 11:14:50,354 - (log3.py) - [WARNING] - 警告です。
2024-12-22 11:14:50,354 - (log3.py) - [ERROR] - ファイルが見つかりません。
2024-12-22 11:14:50,354 - (log3.py) - [CRITICAL] - 緊急事態です。
```

```py:log/warn_handler.log
2024-12-22 11:14:50,354 - (log3.py) - [WARNING] - 警告です。
2024-12-22 11:14:50,354 - (log3.py) - [ERROR] - ファイルが見つかりません。
2024-12-22 11:14:50,354 - (log3.py) - [CRITICAL] - 緊急事態です。
```

## フィルター
```py
import logging

# ロガーを作成
logger = logging.getLogger("example_logger")
logger.setLevel(logging.DEBUG)

# StreamHandler を作成
stream_handler = logging.StreamHandler()  # デフォルトは sys.stderr
# ロガーにハンドラーを追加
logger.addHandler(stream_handler)

# ログフォーマットを設定
formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
stream_handler.setFormatter(formatter)

# ログフィルターの内容をカスタムで定義
class LogFilter(logging.Filter):
  def filter(self,ignore):
    word = ignore.getMessage()
    return 'password' not in word
  
# ログフィルターを設定
logger.addFilter(LogFilter())

# ログを出力
logger.debug("This is a debug message")
logger.info("This is an info message")
logger.warning("password = 'xxxx'")
```

- 出力
```zsh
2024-12-22 11:49:10,951 - example_logger - DEBUG - This is a debug message
2024-12-22 11:49:10,951 - example_logger - INFO - This is an info message

# フィルターに合致する"password = 'xxxx'"が出力されない。
```

## config
- 予めloggingの設定を切り出し、rootモジュールで呼び出せる。
  - コード量の削減による可読性の向上
  - 疎結合による保守性の向上

```shell:ディレクトリ構造
project/
├── main.py
├── logging.json
├── filter.py
```
```py:./logging.json
{
  "version": 1,
  "disable_existing_loggers": false,
  "root": {
    "level": "DEBUG",
    "handlers": [
      "console_handler"
    ]
  },
  "handlers": {
    "console_handler": {
      "class": "logging.StreamHandler",
      "level": "DEBUG",
      "formatter": "simpleFormatter",
      "filters": [
        "LogFilter"
      ],
      "stream": "ext://sys.stdout"
    }
  },
  "formatters": {
    "simpleFormatter": {
      "format": "[%(levelname)s] %(filename)s -> %(message)s"
    }
  },
  "filters": {
    "LogFilter": {
      "()": "filter.LogFilter",
      "words": [
        "password",
        "secret"
      ]
    }
  }
}

```

- カスタムログフィルターの設定
  - `logging.json`の`filters`のキーで参照されている。
```py:./filter.py
import logging

class LogFilter(logging.Filter):
    def __init__(self, words=None):
        super().__init__()
        self.words = words or []

    def filter(self, record):
        # メッセージに特定の単語が含まれている場合は False を返す
        return not any(word in record.getMessage() for word in self.words)
```

```py:main.py
import logging.config
import json

# JSON ファイルをロードしてロギング設定を適用
config_path = 'logging.json'
with open(config_path, 'r') as f:
    config = json.load(f)

logging.config.dictConfig(config)

# ログ出力テスト
logger = logging.getLogger()
logger.debug("This is a debug message.")
logger.info("Sensitive data: password=12345")
logger.warning("This is a warning message.")
logger.error("This is an error message.")

```

### 出力
```zsh
[DEBUG] main.py -> This is a debug message.
[WARNING] main.py -> This is a warning message.
[ERROR] main.py -> This is an error message.

# 「logger.info("Sensitive data: password=12345")」で設定したメッセージは、
# logging.jsonで定義しているwordsの中にある文字列を含んでいるため表示されない。
```

## 参考
https://docs.python.org/ja/3/library/logging.html#logrecord-attributes
https://docs.python.org/ja/3/library/logging.config.html
https://takemikami.com/2016/0611-loggingconfigpython.html
