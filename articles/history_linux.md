---
title: "historyコマンドのナンバーを表示しない方法"
emoji: "🎉"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: []
published: true
---

# historyコマンド
- historyコマンドで行番号を表示させない方法を記載します。

```コマンド
history | awk '{$1=""; print $0}'
```
