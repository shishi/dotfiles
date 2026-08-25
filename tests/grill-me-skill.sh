#!/usr/bin/env bash
# grill-me は grilling を呼ぶ alias なので、Claude/Codex の双方へ 2 skill を
# 配備する。grilling 本体は共通、alias は各 host の呼び出し規約へ合わせる。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  echo "ok: $1"
}

ng() {
  FAIL=$((FAIL + 1))
  echo "NG: $1"
}

for skill in grill-me grilling; do
  claude_skill="${REPO}/claude/skills/${skill}"
  codex_skill="${REPO}/codex/skills/${skill}"

  if [ -f "${claude_skill}/SKILL.md" ] && [ -f "${codex_skill}/SKILL.md" ]; then
    ok "$skill is installed for Claude and Codex"
  else
    ng "$skill is missing from Claude or Codex"
    continue
  fi
done

if diff -ru "${REPO}/claude/skills/grilling" "${REPO}/codex/skills/grilling" >/dev/null; then
  ok "grilling is identical for Claude and Codex"
else
  ng "grilling differs between Claude and Codex"
fi

claude_alias="${REPO}/claude/skills/grill-me/SKILL.md"
codex_alias="${REPO}/codex/skills/grill-me/SKILL.md"
if grep -qF 'disable-model-invocation: true' "$claude_alias" \
  && grep -qF 'Call the Skill tool with "grilling".' "$claude_alias"; then
  ok "Claude grill-me uses the upstream explicit alias"
else
  ng "Claude grill-me no longer uses the upstream explicit alias"
fi

if ! grep -qF 'disable-model-invocation:' "$codex_alias" \
  && grep -qF '../grilling/SKILL.md' "$codex_alias"; then
  ok "Codex grill-me uses a host-compatible grilling reference"
else
  ng "Codex grill-me is not host-compatible"
fi

claude_license="${REPO}/claude/skills/mattpocock-skills.LICENSE"
codex_license="${REPO}/codex/skills/mattpocock-skills.LICENSE"
if [ -f "$claude_license" ] && cmp -s "$claude_license" "$codex_license" \
  && grep -qF 'Copyright (c) 2026 Matt Pocock' "$claude_license"; then
  ok "the upstream MIT license is installed for Claude and Codex"
else
  ng "the upstream MIT license is missing or differs between agents"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
