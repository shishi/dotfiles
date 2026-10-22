---
name: notion-read
description: Notion の URL・ページ・データベースを探す、読む、要約する場合に、REST の本文を絞って取得します。Notion への書き込みや、複数資料の調査計画だけには使いません。
---

# Notion の読み取り

同梱の `notion-read.py` で検索と本文の取得を行います。
Python 3 と curl が必要です。対象 URL / ID が分かる場合は直接読み、
不明な場合は `search` の ID・タイトルから候補を選びます。

## 実行

`NR` にこの `SKILL.md` と同じディレクトリの `notion-read.py` の絶対パスを設定します。
`NOTION_TARGET` と `NOTION_QUERY` には依頼から取得した対象・検索語を設定します。

```sh
python3 "$NR" "$NOTION_TARGET"
python3 "$NR" search "$NOTION_QUERY"
python3 "$NR" "$NOTION_TARGET" --max-depth 1
```

## 取得範囲

- 検索は `has_more` がなくなるまで次ページを取得します。
  integration に共有されていないページは検索結果に含まれません。
- ページの子ブロックとデータベースの行もページ分割して取得します。
  `--max-depth` と `--max-blocks` による未取得・打ち切りを確認します。
  `head` やキーワード抽出は候補発見に使い、全文読了とは数えません。
- テキスト・コード・表のセルを表示します。child page / database は ID を示すだけなので、
  必要なものを別途取得します。画像・添付ファイルなどの内容はこの本文取得に含みません。
- 大きな文書は見出しを確認して必要な節を読みます。
  全文・全件の依頼なら、制限で残った範囲も回収して結果と対応付けます。

## 認証と別経路

token は `NOTION_TOKEN`、`~/.notion_env`、dotfiles ルートの `.notion_env` の順で解決します。
値を出力せず、既存の integration と対象ページの共有範囲を使います。
読めない場合は API のステータス、通信、認証、共有範囲を切り分け、
必ずしも integration 未接続や token 失効とは判断しません。

REST の取得経路が使えない場合や、この出力では扱えない型・query が必要な場合は、
既存の接続ツールで依頼を満たせるか確認します。別経路へ変えても取得範囲を確認します。
この skill は読み取り専用です。書き込みは依頼された Notion 作業の手順へ分けます。

検索・共有範囲・ページ分割は [Notion の検索 API](https://developers.notion.com/reference/post-search)
で確認します。使用する API バージョンはスクリプトの `VERSION` を参照します。
