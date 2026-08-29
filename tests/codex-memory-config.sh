#!/usr/bin/env bash
# Codex native Memories が agent-memory と並行稼働しない設定を検査する。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$REPO/codex/config.toml"
FAILURES=0

pass() { echo "ok: $1"; }
fail() { echo "NG: $1"; FAILURES=$((FAILURES + 1)); }

read_setting() {
  section="$1"
  key="$2"

  awk -v wanted_section="$section" -v wanted_key="$key" '
    {
      line = $0
      sub(/\r$/, "", line)

      header = line
      sub(/^[[:space:]]*/, "", header)
      if (header ~ /^\[[^]]+\][[:space:]]*(#.*)?$/) {
        current_section = header
        sub(/^\[/, "", current_section)
        sub(/\].*$/, "", current_section)
        next
      }

      if (current_section != wanted_section) {
        next
      }
      if (line !~ "^[[:space:]]*" wanted_key "[[:space:]]*=") {
        next
      }

      value = line
      sub("^[[:space:]]*" wanted_key "[[:space:]]*=[[:space:]]*", "", value)
      sub(/[[:space:]]*#.*$/, "", value)
      sub(/[[:space:]]*$/, "", value)
      count++
      last_value = value
    }
    END {
      printf "%d|%s\n", count, last_value
    }
  ' "$CONFIG"
}

[ -f "$CONFIG" ] || {
  echo "fatal: config not found: $CONFIG" >&2
  exit 1
}

check_false() {
  section="$1"
  key="$2"
  actual="$(read_setting "$section" "$key")"

  if [ "$actual" = "1|false" ]; then
    pass "$section.$key is exactly false"
  else
    count="${actual%%|*}"
    value="${actual#*|}"
    fail "$section.$key must occur once with exact value false (count=$count, value=$value)"
  fi
}

check_false "features" "memories"
check_false "memories" "generate_memories"
check_false "memories" "use_memories"
check_false "shell_environment_policy" "ignore_default_excludes"

echo
echo "PASS/FAIL: FAILURES=$FAILURES"
[ "$FAILURES" -eq 0 ]
