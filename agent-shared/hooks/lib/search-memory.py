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


def sections(body):
    """Only explicitly self-contained H2 sections may be delivered separately."""
    frontmatter = re.match(r"\A---\r?\n(.*?)\r?\n---\r?\n", body, re.DOTALL)
    if not frontmatter or not re.search(r"^retrieval: sections\s*$", frontmatter[1], re.MULTILINE):
        return "", []
    starts = []
    offset = 0
    fence = None
    for line in body.splitlines(keepends=True):
        delimiter = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line)
        if delimiter:
            mark, rest = delimiter.groups()
            if fence is None:
                fence = mark
            elif mark[0] == fence[0] and len(mark) >= len(fence) and not rest.strip():
                fence = None
        elif fence is None and line.startswith("## "):
            starts.append(offset)
        offset += len(line)
    if fence or not starts:
        return "", []
    ends = starts[1:] + [len(body)]
    return body[:starts[0]], [body[start:end] for start, end in zip(starts, ends)]


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

    def remember_document(path, body):
        remember(path, body)
        preamble, parts = sections(body)
        for index, part in enumerate(parts):
            remember(f"{path}#section-{index}", preamble + part)

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
                remember_document(path, git(repo, "show", f"{snapshot}:{path}"))
        save()
        return

    prompt = event.get("prompt", "")
    # Treat only complete acknowledgement messages as chatter, not words in real queries.
    if re.fullmatch(r"(?:[\s。！!、,．.]+|承認(?:した|します)?|再開(?:せよ|して|してください)?)+", prompt):
        prompt = ""
    # Latin identifiers and Japanese content words; compound kanji also get two-character terms.
    words = re.findall(r"[A-Za-z][A-Za-z0-9_+-]+|[一-龯]{2,}|[ァ-ヺー]{3,}", prompt)
    terms = {word.casefold() for word in words}
    for word in words:
        if re.fullmatch(r"[一-龯]{3,}", word):
            terms.update(word[i:i + 2] for i in range(len(word) - 1))
    terms -= {"する", "今回", "確認", "作業", "実行", "ユーザー", "アタシ", "the", "and", "for", "is", "to", "of", "in"}
    patterns = {term: re.compile(r"\b" + re.escape(term) + r"\b" if re.fullmatch(r"[a-z]{2}", term)
                                 else re.escape(term)) for term in terms}

    documents = []
    for path in git(repo, "ls-tree", "-r", "--name-only", snapshot).splitlines():
        if not path.endswith(".md") or path in {"MEMORY.md", "CONVENTIONS.md"}:
            continue
        body = git(repo, "show", f"{snapshot}:{path}")
        headings = re.findall(r"^#{1,6} .+", body, re.MULTILINE)
        description = re.search(r"^description: (.+)", body, re.MULTILINE)
        subject = " ".join([path, *(heading for heading in headings if heading.startswith("# ")),
                            description[1] if description else ""]).casefold()
        metadata = " ".join([subject, *headings]).casefold()
        text = body.casefold()
        matches = {term for term, pattern in patterns.items() if pattern.search(text) or pattern.search(metadata)}
        if matches:
            documents.append((path, body, metadata, matches, subject))
    frequency = {term: sum(term in doc[3] for doc in documents) for term in terms}

    def score(doc):
        return sum((3 if patterns[term].search(doc[2]) else 1) * (1 + math.log((len(documents) + 1) / frequency[term]))
                   for term in doc[3])

    # Explicit identifiers in the subject outrank project context; incidental body words do not.
    identifiers = {term for term in terms if re.fullmatch(r"[a-z][a-z0-9_+-]{2,}", term)}
    documents.sort(key=lambda doc: (-sum(bool(patterns[term].search(doc[4])) for term in identifiers),
                                    -(doc[0] == project),
                                    -sum(bool(patterns[term].search(doc[4])) for term in doc[3]),
                                    -sum(bool(patterns[term].search(doc[2])) for term in doc[3]),
                                    -len(doc[3]), -score(doc), doc[0]))
    selected = []
    known = []
    deferred = [doc[0] for doc in documents[MAX_DOCUMENTS:]]
    size = 0
    deliveries = []
    # Choose the relevance set before subtracting already-read content.
    for path, body, *_ in documents[:MAX_DOCUMENTS]:
        if seen.get(path) == hashlib.sha256(body.encode()).hexdigest():
            known.append(path)
            continue
        preamble, parts = sections(body)
        matching = [(index, part) for index, part in enumerate(parts)
                    if any(pattern.search(part.casefold()) for pattern in patterns.values())]
        # A document-level match or shared-condition query needs the whole document.
        shared_text = re.sub(r"\A---\r?\n.*?\r?\n---\r?\n", "", preamble, count=1, flags=re.DOTALL)
        if matching and not any(pattern.search(shared_text.casefold()) for pattern in patterns.values()):
            unread = [(index, part) for index, part in matching
                      if seen.get(f"{path}#section-{index}") != hashlib.sha256((preamble + part).encode()).hexdigest()]
            if not unread:
                known.append(path + "（該当節: " + ", ".join(part.splitlines()[0][3:] for _, part in matching) + "）")
                continue
            excerpt = preamble + "\n".join(part for _, part in unread)
            updates = [(f"{path}#section-{index}", preamble + part) for index, part in unread]
            label = "節取得: " + ", ".join(part.splitlines()[0][3:] for _, part in unread)
        else:
            excerpt = body
            updates = None
            label = "全文取得"
        if size + len(excerpt) <= MAX_BODY_CHARS:
            selected.append((path, body, excerpt, label))
            deliveries.append((path, body, updates))
            size += len(excerpt)
        else:
            deferred.append(path)

    # Scan whole selected documents before emitting any of them or recording delivery.
    for path, body, _, _ in selected:
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
    for path, _, excerpt, label in selected:
        lines.extend([f"\n<retrieved-memory path={json.dumps(path)}>", label, excerpt, "</retrieved-memory>"])
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                           "additionalContext": "\n".join(lines)}}, ensure_ascii=False), flush=True)
    for path, body, updates in deliveries:
        if updates is None:
            remember_document(path, body)
        else:
            for key, content in updates:
                remember(key, content)
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
