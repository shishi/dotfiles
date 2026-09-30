#!/usr/bin/env bash
# review-gate の観点レーン agent について、claude/agents/<name>.md(観点の単一ソース)と
# codex/agents/<name>.toml の developer_instructions が同一本文である契約を検証する。
# Codex の subagent は sandbox で ~/.claude を読めないため toml へ複製せざるを得ず、
# この検査が複製間のドリフトを検出する唯一の機構になる。
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FAIL=0
for name in spec-scope-reviewer correctness-reviewer adversarial-reviewer; do
  md="$REPO/claude/agents/$name.md"
  toml="$REPO/codex/agents/$name.toml"
  [ -f "$toml" ] || { echo "NG: $name (toml missing)"; FAIL=$((FAIL + 1)); continue; }
  if python3 - "$md" "$toml" <<'PY'
import re, sys, tomllib
md = open(sys.argv[1]).read()
body = re.split(r'^---\n.*?^---\n', md, maxsplit=1, flags=re.S | re.M)[1].strip('\n')
ins = tomllib.load(open(sys.argv[2], 'rb'))['developer_instructions'].strip('\n')
sys.exit(0 if body == ins else 1)
PY
  then echo "ok: $name"; else echo "NG: $name (developer_instructions differs from md body)"; FAIL=$((FAIL + 1)); fi
done
[ "$FAIL" = 0 ]
