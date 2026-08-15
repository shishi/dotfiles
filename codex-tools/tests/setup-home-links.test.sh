#!/usr/bin/env bash
set -euo pipefail

CODEX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${CODEX_DIR}/setup-home-links.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/dotfiles/codex/skills" "$TEST_ROOT/home"

HOME="$TEST_ROOT/home" bash "$HELPER" "$TEST_ROOT/dotfiles"

[ ! -d "$TEST_ROOT/home/.codex-setup-home-links.lock" ]
[ -L "$TEST_ROOT/home/.codex" ]
[ -L "$TEST_ROOT/home/.agents/skills" ]
[ "$(cd "$TEST_ROOT/home/.codex" && pwd -P)" = "$(cd "$TEST_ROOT/dotfiles/codex" && pwd -P)" ]
[ "$(cd "$TEST_ROOT/home/.agents/skills" && pwd -P)" = "$(cd "$TEST_ROOT/dotfiles/codex/skills" && pwd -P)" ]

# Existing real directories are never replaced.
mkdir -p "$TEST_ROOT/existing/dotfiles/codex/skills"
mkdir -p "$TEST_ROOT/existing/home/.codex"
printf 'keep\n' > "$TEST_ROOT/existing/home/.codex/marker"
if HOME="$TEST_ROOT/existing/home" \
  bash "$HELPER" "$TEST_ROOT/existing/dotfiles" >/dev/null 2>&1; then
  echo "existing real Codex home was accepted" >&2
  exit 1
fi
[ -f "$TEST_ROOT/existing/home/.codex/marker" ]
[ ! -L "$TEST_ROOT/existing/home/.codex" ]
[ ! -d "$TEST_ROOT/existing/home/.codex-setup-home-links.lock" ]

# If the second link fails, remove only the first link created by this attempt.
mkdir -p "$TEST_ROOT/rollback/dotfiles/codex/skills" "$TEST_ROOT/rollback/home"
mkdir -p "$TEST_ROOT/rollback/bin"
printf '0\n' > "$TEST_ROOT/rollback/ln-count"
REAL_LN="$(command -v ln)"
cat > "$TEST_ROOT/rollback/bin/ln" <<'FAKE_LN'
#!/usr/bin/env bash
count=$(($(cat "$LN_COUNT_FILE") + 1))
printf '%s\n' "$count" > "$LN_COUNT_FILE"
[ "$count" -ne 3 ] || exit 1
exec "$REAL_LN" "$@"
FAKE_LN
chmod +x "$TEST_ROOT/rollback/bin/ln"
if HOME="$TEST_ROOT/rollback/home" \
  LN_COUNT_FILE="$TEST_ROOT/rollback/ln-count" REAL_LN="$REAL_LN" \
  PATH="$TEST_ROOT/rollback/bin:$PATH" \
  bash "$HELPER" "$TEST_ROOT/rollback/dotfiles" >/dev/null 2>&1; then
  echo "second-link failure unexpectedly succeeded" >&2
  exit 1
fi
[ ! -e "$TEST_ROOT/rollback/home/.codex" ]
[ ! -L "$TEST_ROOT/rollback/home/.codex" ]
[ ! -e "$TEST_ROOT/rollback/home/.agents/skills" ]

# If final verification fails, remove both links created by this attempt.
mkdir -p "$TEST_ROOT/verify-rollback/dotfiles/codex/skills" \
  "$TEST_ROOT/verify-rollback/home" "$TEST_ROOT/verify-rollback/bin"
printf '0\n' > "$TEST_ROOT/verify-rollback/ln-count"
cat > "$TEST_ROOT/verify-rollback/bin/ln" <<'FAKE_LN'
#!/usr/bin/env bash
count=$(($(cat "$LN_COUNT_FILE") + 1))
printf '%s\n' "$count" > "$LN_COUNT_FILE"
if [ "$count" -eq 3 ]; then
  "$REAL_LN" "$@" || exit 1
  rmdir "$VERIFY_BREAK_PATH"
  exit 0
fi
exec "$REAL_LN" "$@"
FAKE_LN
chmod +x "$TEST_ROOT/verify-rollback/bin/ln"
if HOME="$TEST_ROOT/verify-rollback/home" \
  LN_COUNT_FILE="$TEST_ROOT/verify-rollback/ln-count" REAL_LN="$REAL_LN" \
  VERIFY_BREAK_PATH="$TEST_ROOT/verify-rollback/dotfiles/codex/skills" \
  PATH="$TEST_ROOT/verify-rollback/bin:$PATH" \
  bash "$HELPER" "$TEST_ROOT/verify-rollback/dotfiles" >/dev/null 2>&1; then
  echo "final verification failure unexpectedly succeeded" >&2
  exit 1
fi
if [ -e "$TEST_ROOT/verify-rollback/home/.agents/skills" ] \
  || [ -L "$TEST_ROOT/verify-rollback/home/.agents/skills" ]; then
  echo "skills link created by failed attempt was left behind" >&2
  exit 1
fi
if [ -e "$TEST_ROOT/verify-rollback/home/.codex" ] \
  || [ -L "$TEST_ROOT/verify-rollback/home/.codex" ]; then
  echo "Codex link created by failed attempt was left behind" >&2
  exit 1
fi

# Cleanup is best-effort and reports an incomplete rollback.
mkdir -p "$TEST_ROOT/cleanup-failure/dotfiles/codex/skills" \
  "$TEST_ROOT/cleanup-failure/home" "$TEST_ROOT/cleanup-failure/bin"
printf '0\n' > "$TEST_ROOT/cleanup-failure/ln-count"
: > "$TEST_ROOT/cleanup-failure/rm-attempts"
cat > "$TEST_ROOT/cleanup-failure/bin/ln" <<'FAKE_LN'
#!/usr/bin/env bash
count=$(($(cat "$LN_COUNT_FILE") + 1))
printf '%s\n' "$count" > "$LN_COUNT_FILE"
if [ "$count" -eq 3 ]; then
  "$REAL_LN" "$@" || exit 1
  rmdir "$VERIFY_BREAK_PATH"
  exit 0
fi
exec "$REAL_LN" "$@"
FAKE_LN
chmod +x "$TEST_ROOT/cleanup-failure/bin/ln"
REAL_RM="$(command -v rm)"
cat > "$TEST_ROOT/cleanup-failure/bin/rm" <<'FAKE_RM'
#!/usr/bin/env bash
if [ "$#" -eq 1 ]; then
  printf '%s\n' "$1" >> "$RM_ATTEMPTS_FILE"
  [ "$1" != "$RM_FAIL_TARGET" ] || exit 1
fi
exec "$REAL_RM" "$@"
FAKE_RM
chmod +x "$TEST_ROOT/cleanup-failure/bin/rm"
if HOME="$TEST_ROOT/cleanup-failure/home" \
  LN_COUNT_FILE="$TEST_ROOT/cleanup-failure/ln-count" REAL_LN="$REAL_LN" \
  VERIFY_BREAK_PATH="$TEST_ROOT/cleanup-failure/dotfiles/codex/skills" \
  RM_ATTEMPTS_FILE="$TEST_ROOT/cleanup-failure/rm-attempts" REAL_RM="$REAL_RM" \
  RM_FAIL_TARGET="$TEST_ROOT/cleanup-failure/home/.agents/skills.rollback-quarantine" \
  PATH="$TEST_ROOT/cleanup-failure/bin:$PATH" \
  bash "$HELPER" "$TEST_ROOT/cleanup-failure/dotfiles" \
  >/dev/null 2>"$TEST_ROOT/cleanup-failure/stderr"; then
  echo "cleanup failure unexpectedly succeeded" >&2
  exit 1
fi
[ -L "$TEST_ROOT/cleanup-failure/home/.agents/skills.rollback-quarantine" ]
[ ! -e "$TEST_ROOT/cleanup-failure/home/.agents/skills" ]
[ ! -e "$TEST_ROOT/cleanup-failure/home/.codex" ]
[ ! -L "$TEST_ROOT/cleanup-failure/home/.codex" ]
grep -F "symlink verification failed" "$TEST_ROOT/cleanup-failure/stderr" >/dev/null \
  || { echo "missing original verification failure diagnostic" >&2; exit 1; }
grep -F "could not remove quarantined link: $TEST_ROOT/cleanup-failure/home/.agents/skills.rollback-quarantine" \
  "$TEST_ROOT/cleanup-failure/stderr" >/dev/null \
  || { echo "missing skills cleanup failure diagnostic" >&2; exit 1; }
grep -F "rollback incomplete" "$TEST_ROOT/cleanup-failure/stderr" >/dev/null \
  || { echo "missing rollback incomplete diagnostic" >&2; exit 1; }
expected_rm_attempts=$(printf '%s\n%s' \
  "$TEST_ROOT/cleanup-failure/home/.agents/skills.rollback-quarantine" \
  "$TEST_ROOT/cleanup-failure/home/.codex.rollback-quarantine")
[ "$(cat "$TEST_ROOT/cleanup-failure/rm-attempts")" = "$expected_rm_attempts" ]

# An existing lock rejects a concurrent setup without touching links.
mkdir -p "$TEST_ROOT/locked/dotfiles/codex/skills" \
  "$TEST_ROOT/locked/home/.codex-setup-home-links.lock"
if HOME="$TEST_ROOT/locked/home" \
  bash "$HELPER" "$TEST_ROOT/locked/dotfiles" \
  >/dev/null 2>"$TEST_ROOT/locked/stderr"; then
  echo "existing setup lock was ignored" >&2
  exit 1
fi
[ -d "$TEST_ROOT/locked/home/.codex-setup-home-links.lock" ]
[ ! -e "$TEST_ROOT/locked/home/.codex" ]
[ ! -L "$TEST_ROOT/locked/home/.codex" ]
[ ! -e "$TEST_ROOT/locked/home/.agents/skills" ]
grep -F "setup already running: $TEST_ROOT/locked/home/.codex-setup-home-links.lock" \
  "$TEST_ROOT/locked/stderr" >/dev/null \
  || { echo "missing existing-lock diagnostic" >&2; exit 1; }

# A link replaced after creation is not owned by this rollback attempt.
mkdir -p "$TEST_ROOT/ownership-change/dotfiles/codex/skills" \
  "$TEST_ROOT/ownership-change/home" "$TEST_ROOT/ownership-change/bin" \
  "$TEST_ROOT/ownership-change/wrong-target"
printf '0\n' > "$TEST_ROOT/ownership-change/ln-count"
cat > "$TEST_ROOT/ownership-change/bin/ln" <<'FAKE_LN'
#!/usr/bin/env bash
count=$(($(cat "$LN_COUNT_FILE") + 1))
printf '%s\n' "$count" > "$LN_COUNT_FILE"
if [ "$count" -eq 3 ]; then
  "$REAL_LN" "$@" || exit 1
  rm "$3" || exit 1
  "$REAL_LN" -s "$VERIFY_WRONG_PATH" "$3"
  exit $?
fi
exec "$REAL_LN" "$@"
FAKE_LN
chmod +x "$TEST_ROOT/ownership-change/bin/ln"
if HOME="$TEST_ROOT/ownership-change/home" \
  LN_COUNT_FILE="$TEST_ROOT/ownership-change/ln-count" REAL_LN="$REAL_LN" \
  VERIFY_WRONG_PATH="$TEST_ROOT/ownership-change/wrong-target" \
  PATH="$TEST_ROOT/ownership-change/bin:$PATH" \
  bash "$HELPER" "$TEST_ROOT/ownership-change/dotfiles" \
  >/dev/null 2>"$TEST_ROOT/ownership-change/stderr"; then
  echo "ownership change unexpectedly succeeded" >&2
  exit 1
fi
if [ ! -L "$TEST_ROOT/ownership-change/home/.agents/skills.rollback-quarantine" ]; then
  echo "ownership-changed skills link was removed" >&2
  exit 1
fi
[ ! -e "$TEST_ROOT/ownership-change/home/.agents/skills" ]
[ "$(readlink "$TEST_ROOT/ownership-change/home/.agents/skills.rollback-quarantine")" \
  = "$TEST_ROOT/ownership-change/wrong-target" ]
[ ! -e "$TEST_ROOT/ownership-change/home/.codex" ]
[ ! -L "$TEST_ROOT/ownership-change/home/.codex" ]
grep -F "ownership changed: $TEST_ROOT/ownership-change/home/.agents/skills" \
  "$TEST_ROOT/ownership-change/stderr" >/dev/null \
  || { echo "missing ownership-change diagnostic" >&2; exit 1; }
grep -F "rollback incomplete" "$TEST_ROOT/ownership-change/stderr" >/dev/null \
  || { echo "missing ownership rollback diagnostic" >&2; exit 1; }
[ ! -d "$TEST_ROOT/ownership-change/home/.codex-setup-home-links.lock" ]

# A Codex link created before ln reports failure is rolled back.
mkdir -p "$TEST_ROOT/codex-post-create-failure/dotfiles/codex/skills" \
  "$TEST_ROOT/codex-post-create-failure/home" \
  "$TEST_ROOT/codex-post-create-failure/bin"
printf '0\n' > "$TEST_ROOT/codex-post-create-failure/ln-count"
cat > "$TEST_ROOT/codex-post-create-failure/bin/ln" <<'FAKE_LN'
#!/usr/bin/env bash
count=$(($(cat "$LN_COUNT_FILE") + 1))
printf '%s\n' "$count" > "$LN_COUNT_FILE"
if [ "$count" -eq 2 ]; then
  "$REAL_LN" "$@" || exit 1
  exit 1
fi
exec "$REAL_LN" "$@"
FAKE_LN
chmod +x "$TEST_ROOT/codex-post-create-failure/bin/ln"
if HOME="$TEST_ROOT/codex-post-create-failure/home" \
  LN_COUNT_FILE="$TEST_ROOT/codex-post-create-failure/ln-count" REAL_LN="$REAL_LN" \
  PATH="$TEST_ROOT/codex-post-create-failure/bin:$PATH" \
  bash "$HELPER" "$TEST_ROOT/codex-post-create-failure/dotfiles" \
  >/dev/null 2>"$TEST_ROOT/codex-post-create-failure/stderr"; then
  echo "Codex post-create failure unexpectedly succeeded" >&2
  exit 1
fi
if [ -e "$TEST_ROOT/codex-post-create-failure/home/.codex" ] \
  || [ -L "$TEST_ROOT/codex-post-create-failure/home/.codex" ]; then
  echo "Codex link created before ln failure was left behind" >&2
  exit 1
fi
[ ! -e "$TEST_ROOT/codex-post-create-failure/home/.agents/skills" ]
[ ! -d "$TEST_ROOT/codex-post-create-failure/home/.codex-setup-home-links.lock" ]
grep -F "could not create $TEST_ROOT/codex-post-create-failure/home/.codex" \
  "$TEST_ROOT/codex-post-create-failure/stderr" >/dev/null \
  || { echo "missing Codex creation failure diagnostic" >&2; exit 1; }

# A skills link created before ln reports failure is rolled back with Codex.
mkdir -p "$TEST_ROOT/skills-post-create-failure/dotfiles/codex/skills" \
  "$TEST_ROOT/skills-post-create-failure/home" \
  "$TEST_ROOT/skills-post-create-failure/bin"
printf '0\n' > "$TEST_ROOT/skills-post-create-failure/ln-count"
cat > "$TEST_ROOT/skills-post-create-failure/bin/ln" <<'FAKE_LN'
#!/usr/bin/env bash
count=$(($(cat "$LN_COUNT_FILE") + 1))
printf '%s\n' "$count" > "$LN_COUNT_FILE"
if [ "$count" -eq 3 ]; then
  "$REAL_LN" "$@" || exit 1
  exit 1
fi
exec "$REAL_LN" "$@"
FAKE_LN
chmod +x "$TEST_ROOT/skills-post-create-failure/bin/ln"
if HOME="$TEST_ROOT/skills-post-create-failure/home" \
  LN_COUNT_FILE="$TEST_ROOT/skills-post-create-failure/ln-count" REAL_LN="$REAL_LN" \
  PATH="$TEST_ROOT/skills-post-create-failure/bin:$PATH" \
  bash "$HELPER" "$TEST_ROOT/skills-post-create-failure/dotfiles" \
  >/dev/null 2>"$TEST_ROOT/skills-post-create-failure/stderr"; then
  echo "skills post-create failure unexpectedly succeeded" >&2
  exit 1
fi
if [ -e "$TEST_ROOT/skills-post-create-failure/home/.agents/skills" ] \
  || [ -L "$TEST_ROOT/skills-post-create-failure/home/.agents/skills" ]; then
  echo "skills link created before ln failure was left behind" >&2
  exit 1
fi
[ ! -e "$TEST_ROOT/skills-post-create-failure/home/.codex" ]
[ ! -L "$TEST_ROOT/skills-post-create-failure/home/.codex" ]
[ ! -d "$TEST_ROOT/skills-post-create-failure/home/.codex-setup-home-links.lock" ]
grep -F "could not create $TEST_ROOT/skills-post-create-failure/home/.agents/skills" \
  "$TEST_ROOT/skills-post-create-failure/stderr" >/dev/null \
  || { echo "missing skills creation failure diagnostic" >&2; exit 1; }

# A wrong Codex link left by failed ln is not adopted or removed.
mkdir -p "$TEST_ROOT/codex-wrong-post-create/dotfiles/codex/skills" \
  "$TEST_ROOT/codex-wrong-post-create/home" \
  "$TEST_ROOT/codex-wrong-post-create/bin" \
  "$TEST_ROOT/codex-wrong-post-create/wrong-target"
printf '0\n' > "$TEST_ROOT/codex-wrong-post-create/ln-count"
cat > "$TEST_ROOT/codex-wrong-post-create/bin/ln" <<'FAKE_LN'
#!/usr/bin/env bash
count=$(($(cat "$LN_COUNT_FILE") + 1))
printf '%s\n' "$count" > "$LN_COUNT_FILE"
if [ "$count" -eq 2 ]; then
  "$REAL_LN" -s "$WRONG_SOURCE" "$3" || exit 1
  exit 1
fi
exec "$REAL_LN" "$@"
FAKE_LN
chmod +x "$TEST_ROOT/codex-wrong-post-create/bin/ln"
if HOME="$TEST_ROOT/codex-wrong-post-create/home" \
  LN_COUNT_FILE="$TEST_ROOT/codex-wrong-post-create/ln-count" REAL_LN="$REAL_LN" \
  WRONG_SOURCE="$TEST_ROOT/codex-wrong-post-create/wrong-target" \
  PATH="$TEST_ROOT/codex-wrong-post-create/bin:$PATH" \
  bash "$HELPER" "$TEST_ROOT/codex-wrong-post-create/dotfiles" \
  >/dev/null 2>"$TEST_ROOT/codex-wrong-post-create/stderr"; then
  echo "wrong Codex post-create failure unexpectedly succeeded" >&2
  exit 1
fi
[ -L "$TEST_ROOT/codex-wrong-post-create/home/.codex" ]
[ "$(readlink "$TEST_ROOT/codex-wrong-post-create/home/.codex")" \
  = "$TEST_ROOT/codex-wrong-post-create/wrong-target" ]
[ ! -e "$TEST_ROOT/codex-wrong-post-create/home/.agents/skills" ]
[ ! -d "$TEST_ROOT/codex-wrong-post-create/home/.codex-setup-home-links.lock" ]
grep -F "could not create $TEST_ROOT/codex-wrong-post-create/home/.codex" \
  "$TEST_ROOT/codex-wrong-post-create/stderr" >/dev/null \
  || { echo "missing wrong Codex creation diagnostic" >&2; exit 1; }
grep -F "ownership changed: $TEST_ROOT/codex-wrong-post-create/home/.codex" \
  "$TEST_ROOT/codex-wrong-post-create/stderr" >/dev/null \
  || { echo "missing wrong Codex ownership diagnostic" >&2; exit 1; }
grep -F "rollback incomplete" "$TEST_ROOT/codex-wrong-post-create/stderr" >/dev/null \
  || { echo "missing wrong Codex rollback diagnostic" >&2; exit 1; }

# A wrong skills link left by failed ln is not adopted or removed.
mkdir -p "$TEST_ROOT/skills-wrong-post-create/dotfiles/codex/skills" \
  "$TEST_ROOT/skills-wrong-post-create/home" \
  "$TEST_ROOT/skills-wrong-post-create/bin" \
  "$TEST_ROOT/skills-wrong-post-create/wrong-target"
printf '0\n' > "$TEST_ROOT/skills-wrong-post-create/ln-count"
cat > "$TEST_ROOT/skills-wrong-post-create/bin/ln" <<'FAKE_LN'
#!/usr/bin/env bash
count=$(($(cat "$LN_COUNT_FILE") + 1))
printf '%s\n' "$count" > "$LN_COUNT_FILE"
if [ "$count" -eq 3 ]; then
  "$REAL_LN" -s "$WRONG_SOURCE" "$3" || exit 1
  exit 1
fi
exec "$REAL_LN" "$@"
FAKE_LN
chmod +x "$TEST_ROOT/skills-wrong-post-create/bin/ln"
if HOME="$TEST_ROOT/skills-wrong-post-create/home" \
  LN_COUNT_FILE="$TEST_ROOT/skills-wrong-post-create/ln-count" REAL_LN="$REAL_LN" \
  WRONG_SOURCE="$TEST_ROOT/skills-wrong-post-create/wrong-target" \
  PATH="$TEST_ROOT/skills-wrong-post-create/bin:$PATH" \
  bash "$HELPER" "$TEST_ROOT/skills-wrong-post-create/dotfiles" \
  >/dev/null 2>"$TEST_ROOT/skills-wrong-post-create/stderr"; then
  echo "wrong skills post-create failure unexpectedly succeeded" >&2
  exit 1
fi
[ -L "$TEST_ROOT/skills-wrong-post-create/home/.agents/skills" ]
[ "$(readlink "$TEST_ROOT/skills-wrong-post-create/home/.agents/skills")" \
  = "$TEST_ROOT/skills-wrong-post-create/wrong-target" ]
[ ! -e "$TEST_ROOT/skills-wrong-post-create/home/.codex" ]
[ ! -L "$TEST_ROOT/skills-wrong-post-create/home/.codex" ]
[ ! -d "$TEST_ROOT/skills-wrong-post-create/home/.codex-setup-home-links.lock" ]
grep -F "could not create $TEST_ROOT/skills-wrong-post-create/home/.agents/skills" \
  "$TEST_ROOT/skills-wrong-post-create/stderr" >/dev/null \
  || { echo "missing wrong skills creation diagnostic" >&2; exit 1; }
grep -F "ownership changed: $TEST_ROOT/skills-wrong-post-create/home/.agents/skills" \
  "$TEST_ROOT/skills-wrong-post-create/stderr" >/dev/null \
  || { echo "missing wrong skills ownership diagnostic" >&2; exit 1; }
grep -F "rollback incomplete" "$TEST_ROOT/skills-wrong-post-create/stderr" >/dev/null \
  || { echo "missing wrong skills rollback diagnostic" >&2; exit 1; }

# A regular file swapped in immediately before cleanup is quarantined, never removed.
mkdir -p "$TEST_ROOT/regular-file-swap/dotfiles/codex/skills" \
  "$TEST_ROOT/regular-file-swap/home" "$TEST_ROOT/regular-file-swap/bin"
printf '0\n' > "$TEST_ROOT/regular-file-swap/ln-count"
cat > "$TEST_ROOT/regular-file-swap/bin/ln" <<'FAKE_LN'
#!/usr/bin/env bash
count=$(($(cat "$LN_COUNT_FILE") + 1))
printf '%s\n' "$count" > "$LN_COUNT_FILE"
[ "$count" -ne 3 ] || exit 1
exec "$REAL_LN" "$@"
FAKE_LN
cat > "$TEST_ROOT/regular-file-swap/bin/mv" <<'FAKE_MV'
#!/usr/bin/env bash
if [ "$1" = "$CODEX_TARGET" ]; then
  rm "$1"
  printf 'foreign\n' > "$1"
fi
exec "$REAL_MV" "$@"
FAKE_MV
chmod +x "$TEST_ROOT/regular-file-swap/bin/ln" \
  "$TEST_ROOT/regular-file-swap/bin/mv"
REAL_MV="$(command -v mv)"
if HOME="$TEST_ROOT/regular-file-swap/home" \
  LN_COUNT_FILE="$TEST_ROOT/regular-file-swap/ln-count" REAL_LN="$REAL_LN" \
  CODEX_TARGET="$TEST_ROOT/regular-file-swap/home/.codex" REAL_MV="$REAL_MV" \
  PATH="$TEST_ROOT/regular-file-swap/bin:$PATH" \
  bash "$HELPER" "$TEST_ROOT/regular-file-swap/dotfiles" \
  >/dev/null 2>"$TEST_ROOT/regular-file-swap/stderr"; then
  echo "regular-file swap unexpectedly succeeded" >&2
  exit 1
fi
[ "$(cat "$TEST_ROOT/regular-file-swap/home/.codex.rollback-quarantine")" = "foreign" ]
grep -F "ownership changed: $TEST_ROOT/regular-file-swap/home/.codex" \
  "$TEST_ROOT/regular-file-swap/stderr" >/dev/null \
  || { echo "missing regular-file ownership diagnostic" >&2; exit 1; }
grep -F "rollback incomplete" "$TEST_ROOT/regular-file-swap/stderr" >/dev/null \
  || { echo "missing regular-file rollback diagnostic" >&2; exit 1; }
