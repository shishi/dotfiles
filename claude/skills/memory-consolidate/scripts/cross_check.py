#!/usr/bin/env python3
"""記憶群の突き合わせ (references/cross-check.md) の機械的な確認を行う。

使い方: cross_check.py extraction|judgments <作業ディレクトリ>

作業ディレクトリには次を置く。
  text/<file>       比べる版の本文 (file は主張の file 欄と同じ "<repo 名>/<相対パス>")
  claims.jsonl      主張の一覧
  skipped.jsonl     主張にしないと決めた文と理由 (任意)
  topics.jsonl      主張ごとの話題 {"id", "topics": [...]}
  judgments.jsonl   (記憶の主張, 話題) ごとの判定

問題を 1 件 1 行で標準出力に出し、問題があれば終了コード 1 で終わる。
"""
import json
from pathlib import Path
import re
import sys

VERDICTS = {"duplicate", "contradiction"}
LIST_ITEM = re.compile(r"^\s*(?:[-*+]|\d+\.)\s+")


def load_jsonl(path, required=True):
    if not path.exists():
        if required:
            sys.exit(f"{path} がありません")
        return []
    with path.open(encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def normalize(text):
    # 改行位置・空白・強調記号・省略記号・句点の有無の違いで、同じ文が別の文に見えないようにする
    return re.sub(r"[\s*`…。]", "", text)


def units(text):
    """本文を、主張になりうる文の単位に分ける。(開始行, 文) を返す。"""
    lines = text.splitlines()
    start = 0
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                start = i + 1
                break
    items = []
    current = None
    for number, line in enumerate(lines[start:], start=start + 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("```") or set(stripped) <= set("|-: "):
            current = None
            continue
        if current is None or LIST_ITEM.match(line) or stripped.startswith("|"):
            current = [number, LIST_ITEM.sub("", line)]
            items.append(current)
        else:
            # 行の境目を残す。詰めると、改行で区切った英語の文がつながって一つの文になる
            current[1] += "\n" + line
    for number, body in items:
        # 日本語は句点で、英語は文末の記号と空白で文に分ける。各文には、その文が始まる行を付ける
        start = 0
        for boundary in [m for m in re.finditer(r"。|(?<=[.!?])\s+", body)] + [None]:
            end = boundary.start() if boundary else len(body)
            sentence = body[start:end]
            if re.search(r"\w", sentence):
                lead = len(sentence) - len(sentence.lstrip())
                yield number + body[:start + lead].count("\n"), sentence.strip()
            start = boundary.end() if boundary else len(body)


def load_claims(work, problems):
    claims = {}
    for claim in load_jsonl(work / "claims.jsonl"):
        if claim.get("id") in claims:
            problems.append(f"duplicate-id {claim.get('id')}")
            continue
        if claim.get("source") not in ("memory", "instruction"):
            problems.append(f"bad-source {claim.get('id')} {claim.get('source')}")
        claims[claim.get("id")] = claim
    return claims


def locate(text_units, fragment, line=None):
    """正規化した断片を含む文の番号を返す。断片は一つの文の中に収まり、1 か所に決まる必要がある。
    同じ語句が複数の文にあるときは、line (文が始まる行) で絞り、なお複数なら文全体が一致する文を選ぶ。
    (当たった数, 文の番号の一覧) を返す。"""
    if not fragment:
        return 0, []
    hits = [k for k, (_, sentence) in enumerate(text_units)
            for _ in range(normalize(sentence).count(fragment))]
    if len(hits) > 1 and line is not None:
        hits = [k for k in hits if text_units[k][0] == line]
    if len(hits) > 1:
        exact = [k for k in hits if normalize(text_units[k][1]) == fragment]
        if len(exact) == 1:
            hits = exact
    return len(hits), hits if len(hits) == 1 else []


def check_extraction(work):
    problems = []
    claims = load_claims(work, problems)
    skipped = load_jsonl(work / "skipped.jsonl", required=False)
    texts = {p.relative_to(work / "text").as_posix(): p.read_text(encoding="utf-8")
             for p in sorted((work / "text").rglob("*")) if p.is_file()}
    file_units = {file: list(units(text)) for file, text in texts.items()}
    covered = {file: set() for file in texts}
    for claim in claims.values():
        file = claim.get("file")
        quote = normalize(claim.get("quote", ""))
        if file not in texts or not quote or quote not in normalize(texts[file]):
            problems.append(f"quote-missing {claim.get('id')} {claim.get('quote')}")
            continue
        hits, where = locate(file_units[file], quote, claim.get("line"))
        if hits > 1:
            # 同じ語句が別の文にもあると、どの文を取り出したかが決まらず、取り出していない文まで済んだことになる
            problems.append(f"ambiguous-quote {claim.get('id')} {claim.get('quote')}")
        elif hits == 0:
            # 文をまたぐ引用は、端にかかっただけの文まで取り出し済みに見せるため、一つの文の中で引用させる
            problems.append(f"quote-spans-sentences {claim.get('id')} {claim.get('quote')}")
        covered[file].update(where)
    for entry in skipped:
        file = entry.get("file")
        hits, where = locate(file_units.get(file, []), normalize(entry.get("text", "")), entry.get("line"))
        if hits != 1 or not entry.get("reason", "").strip():
            problems.append(f"bad-skip {file} {entry.get('text')}")
            continue
        covered[file].update(where)
    for file, items in file_units.items():
        for k, (number, sentence) in enumerate(items):
            if k not in covered[file]:
                problems.append(f"uncovered {file}:{number} {sentence}")
    return problems


def check_judgments(work):
    problems = []
    claims = load_claims(work, problems)
    topics = {}
    for entry in load_jsonl(work / "topics.jsonl"):
        if entry["id"] in topics:
            problems.append(f"duplicate-topics {entry['id']}")
        topics[entry["id"]] = entry.get("topics", [])
    judgments = load_jsonl(work / "judgments.jsonl")
    for claim_id in claims:
        if not topics.get(claim_id):
            problems.append(f"no-topic {claim_id}")
    for claim_id in topics:
        if claim_id not in claims:
            problems.append(f"unknown-claim {claim_id}")
    expected = {(c, t) for c, ts in topics.items()
                if claims.get(c, {}).get("source") == "memory" for t in ts}
    seen = {}
    for line in judgments:
        key = (line["id"], line["topic"])
        if claims.get(line["id"], {}).get("source") != "memory":
            problems.append(f"not-memory {line['id']} {line['topic']}")
            continue
        seen[key] = seen.get(key, 0) + 1
        if key not in expected:
            problems.append(f"unexpected-judgment {line['id']} {line['topic']}")
        for pair in line.get("pairs", []):
            if pair.get("with") not in claims:
                problems.append(f"unknown-partner {line['id']} {pair.get('with')}")
            if pair.get("verdict") not in VERDICTS:
                problems.append(f"bad-verdict {line['id']} {pair.get('with')} {pair.get('verdict')}")
        for other in line.get("outside", []):
            if other not in topics.get(line["id"], []):
                problems.append(f"outside-not-assigned {line['id']} {other}")
    for key in sorted(expected):
        if seen.get(key, 0) == 0:
            problems.append(f"missing-judgment {key[0]} {key[1]}")
    for key, count in sorted(seen.items()):
        if count > 1:
            problems.append(f"duplicate-judgment {key[0]} {key[1]}")
    return problems


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("extraction", "judgments"):
        sys.exit(__doc__)
    work = Path(sys.argv[2])
    problems = check_extraction(work) if sys.argv[1] == "extraction" else check_judgments(work)
    for problem in problems:
        print(problem)
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
