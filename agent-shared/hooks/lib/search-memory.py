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
    return subprocess.check_output(["git", "-C", repo, *args], stderr=subprocess.PIPE).decode("utf-8")


def read_bodies(repo, snapshot, paths):
    """Return what `git show snapshot:path` prints for each path.

    Starting a git process costs tens of milliseconds on Windows, so blobs are read through
    one cat-file batch instead of one git show per file. Anything that is not a blob falls
    back to git show, so its output or failure stays the same.
    """
    batch = subprocess.run(["git", "-C", repo, "cat-file", "--batch"],
                           input="".join(f"{snapshot}:{path}\n" for path in paths).encode("utf-8"),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout
    bodies = {}
    offset = 0
    for path in paths:
        end = batch.index(b"\n", offset)
        # "<oid> <type> <size>" is followed by the content; a missing object has no content.
        header = batch[offset:end].rsplit(b" ", 2)
        offset = end + 1
        if len(header) == 3 and header[2].isdigit():
            start, offset = offset, offset + int(header[2]) + 1
            if offset > len(batch):
                raise ValueError(f"記憶 snapshot の読み取りが途中で切れました: {path}")
            if header[1] == b"blob":
                bodies[path] = batch[start:offset - 1].decode("utf-8")
                continue
        bodies[path] = git(repo, "show", f"{snapshot}:{path}")
    return bodies


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
    cache = core_cache = None
    seen = {}

    def load(path):
        try:
            loaded = json.loads(path.read_text())
        except (ValueError, OSError):
            return {}
        return loaded if isinstance(loaded, dict) else {}

    if session:
        key = hashlib.sha256((str(Path(repo).resolve()) + "\0" + session + "\0" +
                              (event.get("transcript_path") or "")).encode()).hexdigest()
        directory = Path.home() / ".cache" / "agent-memory-lookup"
        # cache は「既読の本文を再注入しない」ための最適化。sandbox 内 (入れ子の claude -p など) で
        # ~/.cache に書けない場合は cache 無しで続け、検索・取得そのものは止めない
        try:
            directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        except OSError:
            pass
        else:
            cache = directory / (key + ".json")
            # Claude's CORE startup hook runs in parallel with the project hook, so it records
            # what it delivered in its own file instead of writing the shared record. Retrievals
            # recorded in the shared file after startup take precedence over the startup record.
            core_cache = directory / (key + ".core.json")
            seen = {**load(core_cache), **load(cache)}

    def remember(path, body):
        seen[path] = hashlib.sha256(body.encode()).hexdigest()

    def remember_document(path, body):
        remember(path, body)
        preamble, parts = sections(body)
        for index, part in enumerate(parts):
            remember(f"{path}#section-{index}", preamble + part)

    def save(target=None):
        target = target or cache
        if not target:
            return
        try:
            temporary = target.with_suffix(f".{os.getpid()}.tmp")
            temporary.write_text(json.dumps(seen))
            temporary.replace(target)
        except OSError:
            pass

    if mode in ("reset", "reset-project", "record-core"):
        # reset-project and record-core are the two halves of Claude's split startup output;
        # each overwrites only its own record with the document it delivered in full (the path
        # argument, possibly empty), so either may finish first.
        seen = {}
        for path in ["CORE.md", project] if mode == "reset" else [project]:
            if path and subprocess.run(["git", "-C", repo, "cat-file", "-e", f"{snapshot}:{path}"],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                remember_document(path, git(repo, "show", f"{snapshot}:{path}"))
        save(core_cache if mode == "record-core" else cache)
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
    terms -= {"する", "今回", "確認", "作業", "実行", "問題", "対応", "ユーザー", "アタシ", "the", "and", "for", "is", "to", "of", "in"}
    patterns = {term: re.compile(r"\b" + re.escape(term) + r"\b" if re.fullmatch(r"[a-z]{2}", term)
                                 else re.escape(term)) for term in terms}

    manual = event.get("memory_lookup_manual", False)
    paths = git(repo, "ls-tree", "-r", "--name-only", snapshot).splitlines()
    # A manual lookup of index paths (one or more, space-separated) retrieves exactly those documents.
    tokens = [prompt] if prompt in paths else prompt.split()
    exact_paths = list(dict.fromkeys(tokens)) if manual and tokens and all(t in paths and t.endswith(".md") for t in tokens) else []
    targets = exact_paths or [path for path in paths if path.endswith(".md")
                                               and path not in {"MEMORY.md", "CONVENTIONS.md"}]
    bodies = read_bodies(repo, snapshot, ["MEMORY.md", *targets])
    index_content = bodies["MEMORY.md"]
    index_entries = {
        path: f"{title} {cue}"
        for title, path, cue in re.findall(r"^- \[([^\]]+)\]\(([^)]+)\)\s*—\s*(.*)$",
                                         index_content, re.MULTILINE)
    }
    documents = []
    for path in exact_paths or paths:
        if not path.endswith(".md") or (not exact_paths and path in {"MEMORY.md", "CONVENTIONS.md"}):
            continue
        body = bodies[path]
        headings = [heading.replace("プロジェクト記憶", "")
                    for heading in re.findall(r"^#{1,6} .+", body, re.MULTILINE)]
        description = re.search(r"^description: (.+)", body, re.MULTILINE)
        subject = " ".join([path, *(heading for heading in headings if heading.startswith("# ")),
                            description[1] if description else "", index_entries.get(path, "")]).casefold()
        metadata = " ".join([subject, *headings]).casefold()
        text = body.casefold()
        matches = {term for term, pattern in patterns.items() if pattern.search(text) or pattern.search(metadata)}
        if matches or path in exact_paths:
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
    candidates = documents
    if exact_paths:
        candidates = [doc for doc in documents if doc[0] in exact_paths]
    selected = []
    known = []
    deferred = [doc[0] for doc in candidates[MAX_DOCUMENTS:]] if manual else []
    size = 0
    deliveries = []
    # Choose the relevance set before subtracting already-read content.
    for path, body, *_ in candidates[:MAX_DOCUMENTS] if manual else documents:
        if seen.get(path) == hashlib.sha256(body.encode()).hexdigest():
            known.append(path)
            continue
        if not manual:
            deferred.append(path)
            continue
        preamble, parts = sections(body)
        matching = [(index, part) for index, part in enumerate(parts)
                    if any(pattern.search(part.casefold()) for pattern in patterns.values())]
        # A document-level match or shared-condition query needs the whole document.
        shared_text = re.sub(r"\A---\r?\n.*?\r?\n---\r?\n", "", preamble, count=1, flags=re.DOTALL)
        if not exact_paths and matching and not any(pattern.search(shared_text.casefold()) for pattern in patterns.values()):
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

    # Scan the index and whole selected documents before emitting any of them or recording delivery.
    for path, body in [("MEMORY.md", index_content), *((path, body) for path, body, _, _ in selected)]:
        result = subprocess.run(["grep", "-Eiq", "--", secret_pattern], input=body.encode(),
                                env={**os.environ, "LC_ALL": "C"})
        if result.returncode != 1:
            raise ValueError(f"秘密情報の可能性または検査失敗: {path}。本文は出力していません")

    lines = [f"[記憶検索] 確定済み記憶の語句検索: {len(documents)}件一致、本文取得{len(selected)}件。",
             "記憶は advisory。現在のユーザー指示と AGENTS.md を優先する。語句一致なので関連記憶の網羅を意味しない。"]
    if exact_paths:
        lines.append(f"取得元の確定 commit: {snapshot}")
    else:
        lines.extend(["<personal-memory-index>", index_content, "</personal-memory-index>",
                  "索引から依頼の対象・操作・制約に合う記憶を確認する。自動取得なし・既読は参照不要を意味しない。",
                  f"必要な本文は git -C {shlex.quote(repo)} show {snapshot}:<索引の相対パス> で取得する。"])
    if known:
        lines.append("既読の同一版: " + ", ".join(known))
    if deferred:
        if manual:
            lines.append(f"取得上限（{MAX_DOCUMENTS}件・本文計{MAX_BODY_CHARS}文字）による未取得: " + ", ".join(deferred))
            lines.append(f"全文が必要なら git -C {shlex.quote(repo)} show {snapshot}:<対象の相対パス> で取得する。")
        else:
            lines.append("語句検索の候補（この hook では本文を注入しない、関連性は未判定）: " + ", ".join(deferred))
    if not manual:
        lines.extend(["本文の自動注入は行わない。候補だけに限定せず索引から意味で選び、必要な未読本文を取得してから判断する。",
                      "既読は注入済みの記録で、理解・適用を確認した記録ではない。",
                      "手動 lookup や git show の読了はこの一覧へ自動反映しない。同版の読了は会話内の取得結果でも確認する。",
                      f"検査付きの全文取得: bash {shlex.quote(str(Path(__file__).resolve().parent.parent / 'inject-memory.sh'))} {shlex.quote(repo)} lookup '<索引で選んだ相対パス>'。必要な記憶はパスを空白で区切って 1 回にまとめて渡す（1 回 {MAX_DOCUMENTS} 件まで）。",
                      f"検索語を渡す手動 lookup も利用できる。パス指定は語句の順位によらず対象を選ぶ。本文計{MAX_BODY_CHARS}文字の上限を超える場合は commit を指定した git show を使う。"])
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
        detail = getattr(error, "stderr", None)
        if detail:
            print(detail.decode("utf-8", "replace").rstrip(), file=sys.stderr)
        sys.exit(2)
