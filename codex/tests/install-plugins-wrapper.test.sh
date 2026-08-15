#!/usr/bin/env bash
set -euo pipefail

CODEX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="${CODEX_DIR}/install-plugins.sh"
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
cat > "$TEST_ROOT/bin/codex" <<'FAKE'
#!/bin/sh
exit 0
FAKE
chmod +x "$TEST_ROOT/bin/python3" "$TEST_ROOT/bin/python" \
  "$TEST_ROOT/bin/codex"

BASH_BIN="$(command -v bash)"
for fixture in no-codex-old-bin no-codex-no-python-bin; do
  mkdir -p "$TEST_ROOT/$fixture"
  cat > "$TEST_ROOT/$fixture/dirname" <<'FAKE'
#!/bin/sh
exec /usr/bin/dirname "$@"
FAKE
  chmod +x "$TEST_ROOT/$fixture/dirname"
done
cat > "$TEST_ROOT/no-codex-old-bin/python3" <<'FAKE'
#!/bin/sh
printf 'invoked\n' > "$PYTHON_PROBE_FILE"
exit 1
FAKE
cp "$TEST_ROOT/no-codex-old-bin/python3" \
  "$TEST_ROOT/no-codex-old-bin/python"
chmod +x "$TEST_ROOT/no-codex-old-bin/python3" \
  "$TEST_ROOT/no-codex-old-bin/python"

set +e
PYTHON_PROBE_FILE="$TEST_ROOT/no-codex-old-python-probe" \
  PATH="$TEST_ROOT/no-codex-old-bin" \
  "$BASH_BIN" "$WRAPPER" >"$TEST_ROOT/no-codex-old-output" 2>&1
status=$?
set -e

[ "$status" -eq 0 ]
grep -F "install-plugins: Codex CLI not found; skipping" \
  "$TEST_ROOT/no-codex-old-output" >/dev/null
[ ! -e "$TEST_ROOT/no-codex-old-python-probe" ]

set +e
PATH="$TEST_ROOT/no-codex-no-python-bin" \
  "$BASH_BIN" "$WRAPPER" >"$TEST_ROOT/no-codex-no-python-output" 2>&1
status=$?
set -e

[ "$status" -eq 0 ]
grep -F "install-plugins: Codex CLI not found; skipping" \
  "$TEST_ROOT/no-codex-no-python-output" >/dev/null

set +e
CAPTURE_FILE="$TEST_ROOT/args" INTERPRETER_FILE="$TEST_ROOT/interpreter" \
  PYTHON3_VERSION_STATUS=0 PYTHON_VERSION_STATUS=0 \
  PYTHON3_RUN_STATUS=7 PYTHON_RUN_STATUS=9 \
  PATH="$TEST_ROOT/bin:$PATH" bash "$WRAPPER" --probe
status=$?
set -e

[ "$status" -eq 7 ]
[ "$(<"$TEST_ROOT/interpreter")" = python3 ]
mapfile -t args < "$TEST_ROOT/args"
[ "${args[0]}" = "${CODEX_DIR}/install_plugins.py" ]
[ "${args[1]}" = "--probe" ]

set +e
CAPTURE_FILE="$TEST_ROOT/fallback-args" \
  INTERPRETER_FILE="$TEST_ROOT/fallback-interpreter" \
  PYTHON3_VERSION_STATUS=1 PYTHON_VERSION_STATUS=0 \
  PYTHON3_RUN_STATUS=7 PYTHON_RUN_STATUS=9 \
  PATH="$TEST_ROOT/bin:$PATH" bash "$WRAPPER" --fallback
status=$?
set -e

[ "$status" -eq 9 ]
[ "$(<"$TEST_ROOT/fallback-interpreter")" = python ]
mapfile -t fallback_args < "$TEST_ROOT/fallback-args"
[ "${fallback_args[0]}" = "${CODEX_DIR}/install_plugins.py" ]
[ "${fallback_args[1]}" = "--fallback" ]

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
grep -F "install-plugins: Python 3.11 or newer is required" \
  "$TEST_ROOT/unsupported-stderr" >/dev/null
[ ! -e "$TEST_ROOT/unsupported-interpreter" ]
