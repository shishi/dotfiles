#!/usr/bin/env bash
# Herdr の CLI が出す手引きに repo の上書きを重ねて skill を生成する契約を検証する。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$REPO/agent-shared/bin/herdr-skills.sh"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL + 1)); echo "NG: $1"; }
assert() { local description="$1"; shift; if "$@"; then ok "$description"; else ng "$description"; fi; }

if [ ! -f "$SCRIPT" ]; then
  echo "NG: herdr-skills implementation is missing"
  exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/herdr-skills.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

DOTFILES="$TMP/dotfiles"
mkdir -p "$DOTFILES/agent-shared/bin" "$DOTFILES/agent-shared/skill-overlays" \
  "$DOTFILES/claude/skills" "$DOTFILES/codex/skills" "$TMP/bin"
cp "$SCRIPT" "$DOTFILES/agent-shared/bin/herdr-skills.sh"

printf -- '---\nname: herdr-core\ndescription: "local core policy"\n---\n\n## Local\n\nlocal core note\n' \
  >"$DOTFILES/agent-shared/skill-overlays/herdr-core.md"
printf -- '---\nname: herdr-app\ndescription: "local app policy"\n---\n' \
  >"$DOTFILES/agent-shared/skill-overlays/herdr-app.md"

# 偽の CLI は、テストが用意したファイルの内容を手引きとして出力する。
cat >"$TMP/bin/hc" <<'EOF'
#!/usr/bin/env bash
[ "$*" = --skill ] || exit 2
[ -f "$FAKE_MANUALS/hc.fail" ] && exit 1
cat "$FAKE_MANUALS/hc.md"
EOF
cat >"$TMP/bin/herdr-app" <<'EOF'
#!/usr/bin/env bash
[ "$*" = --skill ] || exit 2
cat "$FAKE_MANUALS/herdr-app.md"
EOF
chmod +x "$TMP/bin/hc" "$TMP/bin/herdr-app"

MANUALS="$TMP/manuals"
mkdir -p "$MANUALS"
printf '# hc manual\n\nUse hc v1.\n' >"$MANUALS/hc.md"
printf '# herdr-app manual\n\nUse herdr-app v1.\n' >"$MANUALS/herdr-app.md"

run_sync() { # $1=PATH
  PATH="$1" FAKE_MANUALS="$MANUALS" bash "$DOTFILES/agent-shared/bin/herdr-skills.sh" sync \
    >"$TMP/sync.log" 2>&1
}

test_failure() { ! run_sync "$1"; }

has_content() { # $1=file, $2=expected content
  [ -f "$1" ] && [ "$(cat "$1"; printf x)" = "$2"x ]
}

core_v1=$'---\nname: herdr-core\ndescription: "local core policy"\n---\n\n## Local\n\nlocal core note\n\n# hc manual\n\nUse hc v1.\n'
core_v2=$'---\nname: herdr-core\ndescription: "local core policy"\n---\n\n## Local\n\nlocal core note\n\n# hc manual\n\nUse hc v2.\n'
app_v1=$'---\nname: herdr-app\ndescription: "local app policy"\n---\n\n# herdr-app manual\n\nUse herdr-app v1.\n'

assert "sync succeeds when both CLIs print their manuals" run_sync "$TMP/bin:$PATH"
assert "Claude herdr-core skill puts the local overlay before the hc manual" \
  has_content "$DOTFILES/claude/skills/herdr-core/SKILL.md" "$core_v1"
assert "Codex herdr-core skill has the same generated content" \
  has_content "$DOTFILES/codex/skills/herdr-core/SKILL.md" "$core_v1"
assert "Claude herdr-app skill puts the local overlay before the herdr-app manual" \
  has_content "$DOTFILES/claude/skills/herdr-app/SKILL.md" "$app_v1"
assert "Codex herdr-app skill has the same generated content" \
  has_content "$DOTFILES/codex/skills/herdr-app/SKILL.md" "$app_v1"

printf '# hc manual\n\nUse hc v2.\n' >"$MANUALS/hc.md"
run_sync "$TMP/bin:$PATH"
assert "a changed hc manual is taken in with the local overlay kept" \
  has_content "$DOTFILES/claude/skills/herdr-core/SKILL.md" "$core_v2"

: >"$MANUALS/hc.fail"
assert "sync reports failure when hc cannot print its manual" test_failure "$TMP/bin:$PATH"
assert "a failed hc keeps the previous herdr-core skill" \
  has_content "$DOTFILES/claude/skills/herdr-core/SKILL.md" "$core_v2"
rm -f "$MANUALS/hc.fail"

: >"$MANUALS/hc.md"
assert "sync reports failure when hc prints an empty manual" test_failure "$TMP/bin:$PATH"
assert "an empty hc manual keeps the previous herdr-core skill" \
  has_content "$DOTFILES/codex/skills/herdr-core/SKILL.md" "$core_v2"

# CLI が入っていない端末では、既存の skill を残して正常終了する。
mkdir -p "$TMP/no-herdr"
for tool in bash cat mktemp mv rm mkdir dirname; do
  ln -s "$(command -v "$tool")" "$TMP/no-herdr/$tool"
done
assert "sync succeeds without Herdr CLIs" run_sync "$TMP/no-herdr"
assert "a missing hc keeps the previous herdr-core skill" \
  has_content "$DOTFILES/claude/skills/herdr-core/SKILL.md" "$core_v2"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
