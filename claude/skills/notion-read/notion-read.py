#!/usr/bin/env python3
"""Notion ページ/データベースを plain text で読む(MCP を使わずトークン消費を抑える)。

Usage:
  notion-read.py <page-or-database-url-or-id> [--max-depth N] [--max-blocks N]
  notion-read.py search <query>

token の解決順: $NOTION_TOKEN → ~/.notion_env → dotfiles ルートの .notion_env
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time

API = "https://api.notion.com/v1"
VERSION = "2022-06-28"


def token():
    t = os.environ.get("NOTION_TOKEN")
    if t:
        return t.strip()
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.expanduser("~/.notion_env"),
        os.path.normpath(os.path.join(script_dir, "..", "..", "..", ".notion_env")),
    ]
    for p in candidates:
        if os.path.exists(p):
            with open(p) as f:
                return f.read().strip()
    sys.exit("token が見つからない($NOTION_TOKEN / ~/.notion_env / dotfiles/.notion_env)")


def request(path, payload=None, attempts=3, allow_error=False):
    # HTTP は curl で行う。python の urllib は Claude Code の sandbox プロキシ経由で
    # チャンク応答が途中で切れる(IncompleteRead)。curl は同環境で安定して通る。
    # 認証ヘッダーは -K -(stdin の config)で渡し、ps にトークンを出さない。
    config = "\n".join(
        [
            f'header = "Authorization: Bearer {token()}"',
            f'header = "Notion-Version: {VERSION}"',
            'header = "Content-Type: application/json"',
        ]
    )
    for i in range(attempts):
        tmp = None
        cmd = ["curl", "-sS", "-m", "30", "-K", "-", API + path]
        if payload is not None:
            tmp = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
            json.dump(payload, tmp)
            tmp.close()
            cmd += ["--data-binary", "@" + tmp.name]
        try:
            out = subprocess.run(
                cmd, input=config, capture_output=True, text=True, check=True
            ).stdout
            d = json.loads(out)
            if d.get("object") == "error" and not allow_error:
                sys.exit(f"Notion API error: {d.get('code')}: {d.get('message')}")
            return d
        except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
            if i == attempts - 1:
                raise
            print(f"(retry {i + 1}: {type(e).__name__})", file=sys.stderr)
            time.sleep(2 * (i + 1))
        finally:
            if tmp:
                os.unlink(tmp.name)


def to_id(arg):
    m = re.search(r"([0-9a-f]{32})", arg.replace("-", ""))
    if not m:
        sys.exit(f"ID を抽出できない: {arg}")
    h = m.group(1)
    return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:]}"


def rich_text(payload):
    return "".join(x.get("plain_text", "") for x in payload.get("rich_text", []))


PREFIX = {
    "heading_1": "# ",
    "heading_2": "## ",
    "heading_3": "### ",
    "bulleted_list_item": "- ",
    "numbered_list_item": "- ",
    "to_do": "- [ ] ",
    "quote": "> ",
    "toggle": "▸ ",
    "callout": "! ",
}


def walk(block_id, depth, state):
    cursor = None
    while True:
        # page_size を欲張ると応答が大きくなり IncompleteRead が出やすい
        q = "?page_size=50" + (f"&start_cursor={cursor}" if cursor else "")
        d = request(f"/blocks/{block_id}/children{q}")
        for b in d["results"]:
            if state["n"] >= state["max_blocks"]:
                print(f"...(--max-blocks {state['max_blocks']} で打ち切り)")
                return False
            t = b["type"]
            payload = b.get(t, {})
            if t == "child_page":
                txt = f"[child_page: {payload.get('title', '')}] id={b['id']}"
            elif t == "code":
                txt = "```\n" + rich_text(payload) + "\n```"
            else:
                txt = rich_text(payload)
            if txt:
                print("  " * depth + PREFIX.get(t, "") + txt)
                state["n"] += 1
            if b.get("has_children") and t != "child_page" and depth < state["max_depth"]:
                if not walk(b["id"], depth + 1, state):
                    return False
        if not d.get("has_more"):
            return True
        cursor = d.get("next_cursor")


def prop_text(prop):
    t = prop.get("type")
    v = prop.get(t)
    if v is None:
        return ""
    if t in ("title", "rich_text"):
        return "".join(x.get("plain_text", "") for x in v)
    if t in ("select", "status"):
        return v.get("name", "")
    if t == "multi_select":
        return ", ".join(x.get("name", "") for x in v)
    if t == "date":
        return (v.get("start") or "") + (" → " + v["end"] if v.get("end") else "")
    if t == "people":
        return ", ".join(x.get("name", "") for x in v if isinstance(x, dict))
    if t in ("number", "checkbox", "url", "email", "phone_number"):
        return str(v)
    return ""


def query_database(db_id, state):
    cursor = None
    while True:
        payload = {"page_size": 50}
        if cursor:
            payload["start_cursor"] = cursor
        d = request(f"/databases/{db_id}/query", payload)
        for row in d.get("results", []):
            if state["n"] >= state["max_blocks"]:
                print(f"...(--max-blocks {state['max_blocks']} で打ち切り)")
                return
            props = row.get("properties", {})
            title = ""
            rest = []
            for k, p in props.items():
                text = prop_text(p)
                if p.get("type") == "title":
                    title = text
                elif text:
                    rest.append(f"{k}: {text}")
            line = title or "(no title)"
            if rest:
                line += " | " + " | ".join(rest)
            print(f"- {line}  id={row['id']}")
            state["n"] += 1
        if not d.get("has_more"):
            return
        cursor = d.get("next_cursor")


def search(query):
    d = request("/search", {"query": query, "page_size": 20})
    for r in d.get("results", []):
        title = ""
        if r["object"] == "page":
            for p in r.get("properties", {}).values():
                if p.get("type") == "title" and p.get("title"):
                    title = "".join(x.get("plain_text", "") for x in p["title"])
                    break
        elif r["object"] == "database":
            title = "".join(x.get("plain_text", "") for x in r.get("title", []))
        print(f"{r['id']}\t[{r['object']}]\t{title}")


def main():
    parser = argparse.ArgumentParser(
        description="Notion ページ/データベースを plain text で読む"
    )
    parser.add_argument(
        "target",
        nargs="+",
        help="page/database の URL か ID。または `search <query>`",
    )
    parser.add_argument("--max-depth", type=int, default=3)
    parser.add_argument("--max-blocks", type=int, default=300)
    a = parser.parse_args()

    if a.target[0] == "search":
        if len(a.target) < 2:
            parser.error("search にはクエリが必要")
        search(" ".join(a.target[1:]))
        return

    state = {"n": 0, "max_depth": a.max_depth, "max_blocks": a.max_blocks}
    obj_id = to_id(a.target[0])
    # database か page かを判定してから読む(database の id に blocks API は使えない)
    db = request(f"/databases/{obj_id}", allow_error=True)
    if db.get("object") == "database":
        print("# " + ("".join(x.get("plain_text", "") for x in db.get("title", [])) or "(database)"))
        query_database(obj_id, state)
    else:
        walk(obj_id, 0, state)


if __name__ == "__main__":
    main()
