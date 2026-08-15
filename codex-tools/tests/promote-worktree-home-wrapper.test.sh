#!/usr/bin/env bash
set -euo pipefail

CODEX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="${CODEX_DIR}/promote-worktree-home.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/bin"
cat > "$TEST_ROOT/bin/python3" <<'FAKE'
#!/usr/bin/env bash
name="$(basename "$0")"
if [ "${1-}" = "-c" ]; then
  if [ "$name" = python3 ]; then
    exit "$PYTHON3_VERSION_STATUS"
  fi
  exit "$PYTHON_VERSION_STATUS"
fi
printf '%s\n' "$@" > "$CAPTURE_FILE"
printf '%s\n' "$name" > "$INTERPRETER_FILE"
if [ "$name" = python3 ]; then
  exit "$PYTHON3_RUN_STATUS"
fi
exit "$PYTHON_RUN_STATUS"
FAKE
cp "$TEST_ROOT/bin/python3" "$TEST_ROOT/bin/python"
chmod +x "$TEST_ROOT/bin/python3" "$TEST_ROOT/bin/python"

set +e
CAPTURE_FILE="$TEST_ROOT/args" INTERPRETER_FILE="$TEST_ROOT/interpreter" \
  PYTHON3_VERSION_STATUS=0 PYTHON_VERSION_STATUS=0 \
  PYTHON3_RUN_STATUS=8 PYTHON_RUN_STATUS=9 \
  PATH="$TEST_ROOT/bin:$PATH" bash "$WRAPPER"
status=$?
set -e

[ "$status" -eq 8 ]
[ "$(<"$TEST_ROOT/interpreter")" = python3 ]
mapfile -t args < "$TEST_ROOT/args"
[ "${args[0]}" = "${CODEX_DIR}/promote_worktree_home.py" ]
[ "${#args[@]}" -eq 1 ]

set +e
CAPTURE_FILE="$TEST_ROOT/fallback-args" \
  INTERPRETER_FILE="$TEST_ROOT/fallback-interpreter" \
  PYTHON3_VERSION_STATUS=1 PYTHON_VERSION_STATUS=0 \
  PYTHON3_RUN_STATUS=8 PYTHON_RUN_STATUS=9 \
  PATH="$TEST_ROOT/bin:$PATH" bash "$WRAPPER"
status=$?
set -e

[ "$status" -eq 9 ]
[ "$(<"$TEST_ROOT/fallback-interpreter")" = python ]
mapfile -t fallback_args < "$TEST_ROOT/fallback-args"
[ "${fallback_args[0]}" = "${CODEX_DIR}/promote_worktree_home.py" ]

set +e
CAPTURE_FILE="$TEST_ROOT/unsupported-args" \
  INTERPRETER_FILE="$TEST_ROOT/unsupported-interpreter" \
  PYTHON3_VERSION_STATUS=1 PYTHON_VERSION_STATUS=1 \
  PYTHON3_RUN_STATUS=0 PYTHON_RUN_STATUS=0 \
  PATH="$TEST_ROOT/bin:$PATH" bash "$WRAPPER" \
  >"$TEST_ROOT/unsupported-stdout" 2>"$TEST_ROOT/unsupported-stderr"
status=$?
set -e

[ "$status" -eq 1 ]
grep -F "promote-worktree-home: Python 3.11 or newer is required" \
  "$TEST_ROOT/unsupported-stderr" >/dev/null
[ ! -e "$TEST_ROOT/unsupported-interpreter" ]
