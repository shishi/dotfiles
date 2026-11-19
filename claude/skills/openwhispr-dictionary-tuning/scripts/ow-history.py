"""OpenWhispr の文字起こし履歴を読み取り専用で書き出す。

使い方: python ow-history.py [--since "2026-01-01 00:00:00"] [--json | --raw-only]
  --since     記録時刻 (UTC、"YYYY-MM-DD HH:MM:SS" の文字列比較) がこれ以降の行だけを出す
  --json      id・記録時刻・Whisper の生の文字 (raw)・整形後に貼り付けた文字 (text) の配列
  --raw-only  Whisper の生の文字だけの配列 (空の行は除く)。ow-cleanup-check.mjs の入力になる
アプリは貼り付けた先のアプリ名や、利用者があとで直した文を保存しない。
"""
import argparse
import json
import os
import sqlite3
import sys

# Windows で出力先がファイルやパイプのとき、既定の文字コードでは日本語が化けるので UTF-8 に固定する
sys.stdout.reconfigure(encoding="utf-8")
db = os.path.join(os.environ["APPDATA"], "open-whispr", "transcriptions.db")
ap = argparse.ArgumentParser()
ap.add_argument("--since", default="")
ap.add_argument("--json", action="store_true")
ap.add_argument("--raw-only", action="store_true")
args = ap.parse_args()
con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
rows = con.execute(
    "select id, created_at, raw_text, text from transcriptions "
    "where status = 'completed' and deleted_at is null and created_at >= ? order by id",
    (args.since,),
).fetchall()
if args.raw_only:
    print(json.dumps([r[2] for r in rows if r[2] and r[2].strip()], ensure_ascii=False, indent=1))
elif args.json:
    print(json.dumps([dict(zip(["id", "created_at", "raw", "text"], r)) for r in rows], ensure_ascii=False, indent=1))
else:
    for i, ts, raw, text in rows:
        print(f"{i}\t{ts}\t{raw or ''}\t{text or ''}")
