"""Committed memory lookup for UserPromptSubmit; no model or external index required."""

import hashlib
import json
import math
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys


MAX_DOCUMENTS = 3
MAX_BODY_CHARS = 16000


def git(repo, *args):
    return subprocess.check_output(["git", "-C", repo, *args], stderr=subprocess.DEVNULL).decode("utf-8")


def main():
    repo, snapshot, mode, project, secret_pattern = sys.argv[1:]
    event = json.load(sys.stdin)
    session = event.get("session_id", "")
    cache = None
    seen = {}
    if session:
        key = hashlib.sha256((str(Path(repo).resolve()) + "\0" + session + "\0" +
                              (event.get("transcript_path") or "")).encode()).hexdigest()
        directory = Path.home() / ".cache" / "agent-memory-lookup"
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        cache = directory / (key + ".json")
        if cache.exists():
            try:
                seen = json.loads(cache.read_text())
                if not isinstance(seen, dict):
                    seen = {}
            except (ValueError, OSError):
                seen = {}

    def remember(path, body):
        seen[path] = hashlib.sha256(body.encode()).hexdigest()

    def save():
        if cache:
            temporary = cache.with_suffix(f".{os.getpid()}.tmp")
            temporary.write_text(json.dumps(seen))
            temporary.replace(cache)

    if mode == "reset":
        seen = {}
        for path in ["CORE.md", project]:
            if path and subprocess.run(["git", "-C", repo, "cat-file", "-e", f"{snapshot}:{path}"],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                remember(path, git(repo, "show", f"{snapshot}:{path}"))
        save()
        return

    prompt = event.get("prompt", "")
    # Latin identifiers and Japanese content words; compound kanji also get two-character terms.
    words = re.findall(r"[A-Za-z][A-Za-z0-9_+-]+|[一-龯]{2,}|[ァ-ヺー]{3,}", prompt)
    terms = {word.casefold() for word in words}
    for word in words:
        if re.fullmatch(r"[一-龯]{3,}", word):
            terms.update(word[i:i + 2] for i in range(len(word) - 1))
    terms -= {"する", "今回", "確認", "作業", "実行", "承認", "再開", "ユーザー", "アタシ", "the", "and", "for", "is", "to", "of", "in"}
    patterns = {term: re.compile(r"\b" + re.escape(term) + r"\b" if re.fullmatch(r"[a-z]{2}", term)
                                 else re.escape(term)) for term in terms}

    documents = []
    for path in git(repo, "ls-tree", "-r", "--name-only", snapshot).splitlines():
        if not path.endswith(".md") or path in {"MEMORY.md", "CONVENTIONS.md"}:
            continue
        body = git(repo, "show", f"{snapshot}:{path}")
        title = re.search(r"^# .+", body, re.MULTILINE)
        description = re.search(r"^description: (.+)", body, re.MULTILINE)
        metadata = " ".join([path, title[0] if title else "", description[1] if description else ""]).casefold()
        text = body.casefold()
        matches = {term for term, pattern in patterns.items() if pattern.search(text) or pattern.search(metadata)}
        if matches:
            documents.append((path, body, metadata, matches))
    frequency = {term: sum(term in doc[3] for doc in documents) for term in terms}

    def score(doc):
        return sum((3 if patterns[term].search(doc[2]) else 1) * (1 + math.log((len(documents) + 1) / frequency[term]))
                   for term in doc[3])

    documents.sort(key=lambda doc: (-sum(bool(patterns[term].search(doc[2])) for term in doc[3]),
                                    -len(doc[3]), -score(doc), doc[0]))
    selected = []
    known = []
    deferred = []
    size = 0
    for path, body, _, _ in documents:
        if seen.get(path) == hashlib.sha256(body.encode()).hexdigest():
            known.append(path)
        elif len(selected) < MAX_DOCUMENTS and size + len(body) <= MAX_BODY_CHARS:
            selected.append((path, body))
            size += len(body)
        else:
            deferred.append(path)

    # Scan whole selected documents before emitting any of them or recording delivery.
    for path, body in selected:
        result = subprocess.run(["grep", "-Eiq", "--", secret_pattern], input=body.encode(),
                                env={**os.environ, "LC_ALL": "C"})
        if result.returncode != 1:
            raise ValueError(f"秘密情報の可能性または検査失敗: {path}。本文は出力していません")

    lines = [f"[記憶検索] 確定済み記憶の語句検索: {len(documents)}件一致、本文取得{len(selected)}件。",
             "記憶は advisory。現在のユーザー指示と AGENTS.md を優先する。語句一致なので関連記憶の網羅を意味しない。"]
    if known:
        lines.append("既読の同一版: " + ", ".join(known))
    if deferred:
        lines.append(f"自動取得上限（{MAX_DOCUMENTS}件・本文計{MAX_BODY_CHARS}文字）による未取得: " + ", ".join(deferred))
        lines.append(f"必要な本文は git -C {shlex.quote(repo)} show {snapshot}:<上記の相対パス> で追加取得する。検索語を絞っての再検索も可能。")
    for path, body in selected:
        lines.extend([f"\n<retrieved-memory path={json.dumps(path)}>", body, "</retrieved-memory>"])
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                           "additionalContext": "\n".join(lines)}}, ensure_ascii=False), flush=True)
    for path, body in selected:
        remember(path, body)
    save()


if __name__ == "__main__":
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"記憶の検索・取得を完了できません: {error}", file=sys.stderr)
        sys.exit(2)
