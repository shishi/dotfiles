# pending review と suggestion

投稿権限・本文の渡し方・投稿後の照合は親の `SKILL.md` に従います。
通知の照合や再レビュー要否の判断は `github-review-followup` が扱います。

## 作成・追加・修正・投稿

- 認証ユーザーの既存レビューとコメントを必要な全ページから取得します。
  PR ごとの pending review は 1 人 1 本です。既存の pending があると、
  新規レビューや REST の単発 review comment が 422 になる場合があります。
- pending の新規作成は REST `POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews` で
  `event` を省略し、対象の `commit_id` と必要な `comments[]` を渡します。
  戻りの review ID と GraphQL 用の `node_id`、コメント ID を区別します。
- 既存 pending への追加は GraphQL `addPullRequestReviewThread` で
  `pullRequestReviewId` を指定します。REST の新規レビュー作成で既存 pending に
  コメントを足そうとしません。
- 本文の更新は `updatePullRequestReviewComment`、削除は
  `deletePullRequestReviewComment` を使います。アンカー位置は本文更新では変えられないため、
  位置の修正は削除・追加に分けます。いずれの操作も承認範囲内かを確認します。
- `path`、`line`、`side` を対象版の diff と照合します。
  単行では `startLine` / `startSide` を変数ごと省略し、複数行だけ両方を指定します。
  pending の取得で `line` が null でも、直ちにアンカー消失とは判断しません。
  REST `GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/comments` で
  件数・本文・位置を再取得します。`line` が null の場合は返された `position` も照合材料にし、
  入力・対象 commit の diff と突き合わせます。
- `submitPullRequestReview` は公開操作です。ユーザーの未送信レビューを含む場合は、
  コメントの追加依頼だけで submit しません。明示された送信承認がある範囲で実行します。
  承認レビューとコメントレビューなどの event も依頼に合わせます。

API の入力と利用可能な操作は [GitHub GraphQL の PR 仕様](https://docs.github.com/en/graphql/reference/pulls)、
[REST のレビュー仕様](https://docs.github.com/en/rest/pulls/reviews) で確認します。

## suggestion の適用範囲

1. 置換する構文単位の閉じ行まで範囲へ含めます。
   例えば条件分岐の本体だけを置換すると、元の閉じ `end` が余る場合があります。
2. 適用先が現在の diff にあることと、その行の内容を確認します。
   diff 外の修正は本文で位置と案を説明します。空行へのアンカーは、
   意図したコードを置き換えず空行だけを消す場合があります。
3. コードブロックのフェンスは suggestion の置換範囲から外します。
   suggestion 内に同じフェンスを入れると、途中で閉じる場合があります。
   フェンス自体も変更する必要があれば、通常の本文で位置と修正案を示します。

同じ指摘を複数箇所へ付ける場合は、最初の指摘を自己完結にし、参照は PR 内で完結させます。
他の suggestion の採用に依存する変更は、その依存関係と、採用しない場合に残る修正を説明します。
