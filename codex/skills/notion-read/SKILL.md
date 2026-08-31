---
name: notion-read
description: Use when the user asks to read, summarize, or look up a Notion page or database — a notion.so URL, 「Notion のページ読んで」「仕様は Notion にある」 — or when task context points to a Notion document. Read-only. Do not use the Notion MCP server for reading; this is the token-cheap path.
---

# Notion Read(API 直読みでトークン節約)

## Overview

Notion MCP の代わりに REST API を CLI で叩き、plain text だけを context に入れる。結果はパイプで絞ってから読む。

## 使い方

```bash
NR=~/.codex/skills/notion-read/notion-read.py

# ページ/データベースを読む(URL でも ID でも可)
python3 $NR "https://www.notion.so/xxx-<32hex>"

# キーワードで探す(id と title の一覧が返る)
python3 $NR search "デモシナリオ"

# 大きいページは絞ってから読む
python3 $NR <url> --max-depth 1 | head -40
python3 $NR <url> | grep -A2 "キーワード"
```

スクリプトは python3 標準ライブラリ+curl のみで動く。

## トークン節約の型

1. `search` で目的のページ id を特定する
2. `--max-depth=1` か `head` で構造を掴む
3. 必要な節だけ `grep` で抜く。全文を context に入れるのは最後の手段

## 認証

token の解決順: `$NOTION_TOKEN` → `~/.notion_env` → dotfiles ルートの `.notion_env`(ファイルは token 文字列 1 行)。
readonly integration を想定。読めないページは integration が接続されていない(ページの ⋯ → 接続 で追加)。

## 制約

- 読み取り専用。書き込みはしない
- child_page の中身は自動では辿らない(id が表示されるので必要なら別途読む)
- database は行ごとに「タイトル | プロパティ: 値」の 1 行表示(plain text)。リッチな型やフィルタ付き query が要るときだけ MCP を検討する
