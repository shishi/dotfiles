#!/usr/bin/env bash
# codex-delegate skill の静的検査。
# 使い方: bash tests/codex-delegate.sh
#
# codex を起動しない。実行を伴う検証(sandbox が効くか・記憶が書かれないか・
# timeout 後の停止が届くか等)は spec の「検証」節が担い、OpenAI 側の利用枠を要する。
# ここで見るのは、リポジトリ内のファイルだけで判定できることに限る。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$REPO/claude/skills/codex-delegate"
SKILL="$SKILL_DIR/SKILL.md"
SCHEMA="$SKILL_DIR/schema.json"
SETTINGS="$REPO/claude/settings.json"
CLAUDE_MD="$REPO/claude/CLAUDE.md"
INSTALLER="$REPO/claude/install-plugins.sh"
FAILURES=0

pass() { echo "  ok: $1"; }
fail() { echo "  NG: $1"; FAILURES=$((FAILURES + 1)); }

check() { # check <desc> <cmd...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

check_not() { # 成功したら NG
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$desc"; else pass "$desc"; fi
}

command -v jq >/dev/null 2>&1 || { echo "codex-delegate: jq not found; cannot run"; exit 2; }

echo "# schema.json (出力契約)"

check "存在する" test -f "$SCHEMA"
check "valid JSON" jq -e . "$SCHEMA"
check "additionalProperties が false" \
  jq -e '.additionalProperties == false' "$SCHEMA"
check "type が object" jq -e '.type == "object"' "$SCHEMA"
# 構造化出力は全キーの明示を要求するため、properties と required は同一集合でなければならない
check "properties と required が同一集合" \
  jq -e '(.properties | keys | sort) == (.required | sort)' "$SCHEMA"
check "required が 6 プロパティ" jq -e '(.required | length) == 6' "$SCHEMA"
check "status の enum が done/partial/blocked" \
  jq -e '.properties.status.enum == ["done","partial","blocked"]' "$SCHEMA"
# maxLength / maxItems だけが実効の上限。description に書いた長さの指示は注釈であり
# 適合検査の対象にならないため、上限として数えない
check "summary に maxLength" jq -e '.properties.summary.maxLength > 0' "$SCHEMA"
for arr in changed_files findings next_steps blockers; do
  check "$arr に maxItems" jq -e --arg a "$arr" '.properties[$a].maxItems > 0' "$SCHEMA"
  check "$arr の items に maxLength" \
    jq -e --arg a "$arr" '.properties[$a].items.maxLength > 0' "$SCHEMA"
done
# 上限の合計 = 1 回の委譲が Claude の context へ加えうる最大量。SKILL.md と plan が
# 22,600 文字と書いているので、schema 側を緩めたらここで落ちる
check "上限の合計が 22,600 文字を超えない" jq -e '
  (.properties.summary.maxLength)
  + (.properties.changed_files.maxItems * .properties.changed_files.items.maxLength)
  + (.properties.findings.maxItems     * .properties.findings.items.maxLength)
  + (.properties.next_steps.maxItems   * .properties.next_steps.items.maxLength)
  + (.properties.blockers.maxItems     * .properties.blockers.items.maxLength)
  <= 22600' "$SCHEMA"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "codex-delegate: all checks passed"
else
  echo "codex-delegate: $FAILURES check(s) failed"
fi
[ "$FAILURES" -eq 0 ]
