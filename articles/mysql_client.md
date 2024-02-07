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
mysql.server stop
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

- 作成したユーザー,ホスト名の確認
```
SELECT user,host FROM mysql.user;
```

- ユーザーに権限付与
```
Grant ALL PRIVILEGES ON *.* TO 'user1'@'locqhost' ;
```

- rootユーザにパスワード割り当て 
```
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '新しいパスワード';
```



# DBやテーブルの作成、参照、消し方