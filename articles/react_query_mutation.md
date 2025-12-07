---
title: "TanStack QueryとuseMutationの使い方"
emoji: "🎉"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["React", "TypeScript", "TanStack Query"]
published: false
---

![](/images/redux/redux.png =450x)

## 1. 記事を書いた背景

実装をしていて何となくどんな処理をしているのかは分かるのですが、体系的に整理したいと思いノートがわりにブログとして書いています。

## 2. 対象読者

- TanStack Query の初学者,未経験者(自分みたいな)

### 3. 書くこと

- TanStack Query とは？
- どんなコンポーネントがあるか
- 基礎的な CRUD の実装(API は用意されてるモノ)

## 4. TanStack Query とは？

- React の状態管理ライブラリで API 側との通信におけるキャッシュ、更新、 ローディング、 エラーハンドリング等を行う。
- fetch や axios などデータ取得の処理と一緒に使われる。

@[card](https://tanstack.com/query/latest/docs/framework/react/overview)
@[card](https://tanstack.com/query/latest/docs/framework/react/examples/basic)

## 5. どんなコンポーネントがあるか(ここ AI 使ってます)
実装例は公式のものをベースに少し変えてます。
@[card](https://tanstack.com/query/latest/docs/framework/react/examples/basic?path=examples%2Freact%2Fbasic%2Fsrc%2Findex.tsx)

- QueryClient
  - クライアント
  - キャッシュの管理、設定を保持
  - Query Options
    - staleTime: データが古くなるまでの時間
    - cacheTime: キャッシュが削除されるまでの時間
    - refetchOnWindowFocus: ウィンドウフォーカス時の再取得
    - retry: 失敗時のリトライ回数
```tsx
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5000, // データ取得して5秒以降後の再レンダリングはAPIを叩く
      gcTime: 10 * 60 * 1000, // モーダルを閉じたりページ遷移でアンマウントしても10分はキャッシュ保持
      refetchOnWindowFocus: true, // 別タブ見てて戻ってきた場合は自動で最新データ取得
      retry: 3, // エラー時に3回リトライ
      retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000), // 指数バックオフ
    },
    mutations: {
      retry: 3, // エラー時に3回リトライ
      retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000), // 指数バックオフ
    },
  },
})
```

- useQueryClient
  - QueryClient インスタンスにアクセスするフック
  - キャッシュの手動操作（invalidate、setQueryData など）


- QueryClientProvider
  - React の Context Provider
  - app.tsx で QueryClient を全体に提供



- useQuery
  - データ取得(GET)用のフック
    - 実装例はカスタムフック
  - ローディング、エラー、データの状態を返す
  - 自動的にキャッシュと再取得を管理


- useMutation
  - データ更新(POST/PUT/DELETE)用のフック
  - サーバーへの変更を伴う操作に使用
  - 成功/失敗時のコールバック、楽観的更新が可能


- QueryKey
  - クエリを一意に識別するキー
  - 配列形式（例: ['todos', { status: 'active' }]）
  - キャッシュの管理、無効化に使用
- Query Function
  - 実際のデータ取得処理を行う関数
  - fetch、axios などを使って実装
  - Promise を返す必要がある
- DevTools (React Query DevTools)
  - 開発用ツール
  - キャッシュ状態の可視化、デバッグ支援
- Invalidation
  - queryClient.invalidateQueries()でキャッシュを無効化
  - データ更新後に関連するクエリを再取得
- Prefetching
  - queryClient.prefetchQuery()
  - ユーザーアクション前にデータをロード

## まとめ

## 参考

@[card](https://thinkit.co.jp/article/18240)
