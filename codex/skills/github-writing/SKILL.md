---
name: github-writing
description: GitHub の issue・PR・コメント・レビュー本文の投稿や更新を明示的に依頼されたときに使います。読取だけや草案作成だけでは使いません。
---

# GitHub 本文の投稿と更新

投稿先と本文を確定し、送信した本文を同じ対象から取得して照合します。この skill の選択自体は投稿の承認になりません。issue の構成・草案は `writing-issues`、文章の推敲は `writing-prose` に従います。

## 送信前

1. GitHub ホスト、repository、issue / PR 番号、本文かコメントかを特定します。更新では対象 ID と現在の本文も取得します。
2. 依頼で許可された操作とアカウントを確認します。ユーザー指定の connector・API・CLI を優先し、宛先と全文を `review-gate` でレビューします。既にある承認は取り直しません。
3. 複数行本文は構造化引数で渡します。CLI を使う場合は以下の方法で本文を渡し、シェルのコードへ埋め込みません。

## gh CLI の本文受け渡し

| 操作 | 本文の渡し方 |
|---|---|
| `gh issue/pr create`・`edit`・`comment` | 確定本文を UTF-8 の一時ファイルへ保存し、確認した絶対パスを `--body-file` に渡します |
| REST の本文更新 | JSON serializer で `{"body": 本文}` を作り、`gh api --method PATCH <endpoint> --input <絶対パス>` に渡します |
| GraphQL | `query` と `variables` を JSON にし、`gh api graphql --input <絶対パス>` に渡します |

一時ファイルは送信する環境から読み直して本文を確認します。sandbox や別プロセスの一時ディレクトリを推測して組み立てません。stdin を使う環境では `--body-file -` / `--input -` に同じ本文を渡せます。文字コードと改行が保持されることを確認します。

`gh api -f body=@-` は禁止です。`-f` はリテラル文字列なので、本文を `@-` に置き換えます。`-F` は別の型変換規則です。本文を含む複雑な payload には JSON と `--input` を使います。[gh api の仕様](https://cli.github.com/manual/gh_api)

## pending review にコメントを追加する場合

- 認証ユーザーの pending review を先に取得します。PR ごとの pending review は 1 人 1 本です。既存 review があると、新規 review 作成や REST の単発 review comment が 422 になる場合があります。
- 既存 pending への追加は GraphQL `addPullRequestReviewThread` の `pullRequestReviewId` を指定します。review の `node_id` とコメントの ID を混同しません。
- `path`、`line`、`side` を現在の PR diff と照合します。単行は `startLine` / `startSide` を変数ごと省略します。複数行だけ両方を指定します。
- suggestion は適用先が diff にある場合に使います。diff 外の修正は本文で位置と変更案を説明します。
- 本文差し替えには `updatePullRequestReviewComment`、削除には `deletePullRequestReviewComment` とコメント ID を使います。削除も依頼の範囲内に限ります。
- submit は公開操作です。ユーザーが未送信の review を保持している場合、追加依頼だけで submit しません。明示された送信承認があるときだけ `submitPullRequestReview` を実行します。レビュー一覧・コメント一覧は必要な全ページを取得します。

各 mutation の入力は [GitHub の PR GraphQL 仕様](https://docs.github.com/en/graphql/reference/pulls) で確認します。

## 送信後

同じ本文・コメント ID から本文を再取得し、送信した原文と比較します。親 issue / PR 本文の取得をコメントの確認に代用しません。改行を正規化する場合は観測された輸送上の差だけに限定し、本文全体への `trim` で欠落を隠しません。

タイムアウトや 422、submit のエラーでは、再送前に現在の本文・review state を取得します。初回が成功していれば重複投稿や再 submit をしません。不一致があれば元の依頼の範囲で修正し、再取得して確認します。URL と終了コードだけでは完了にしません。
