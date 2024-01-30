---
title: "SQLの基本コマンド"
emoji: "🌟"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: []
published: false
---

# SQLの種類

# MYSQLのインストール

# mysqlへのログイン,ログアウト
```
musql.server start
mysql -u root 
quit / ext
mysql.server 
```


# SQL操作
```
SHOW DATABASES;
USE {DB名};
SHOW TABLES;
DESC {テーブル名}
DROP TABLE {テーブル名};

```


# MYSQLのユーザー作成〜権限付与

- ユーザー作成
```
CREATE USER '{ユーザー名}@'{ホスト名}' IDENTIFIED BY '{パスワード}';
```

- 作成したユーザーの確認
```
SHOW user.host FROM mysql.user
```

# DBやテーブルの作成、参照、消し方