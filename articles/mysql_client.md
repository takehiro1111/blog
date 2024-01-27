---
title: "SQLの基本コマンド"
emoji: "🌟"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: []
published: false
---
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