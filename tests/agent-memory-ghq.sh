#!/usr/bin/env bash
# agent-memory の配置先を決める優先順位だけを検証する。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="$REPO/agent-shared/bin/resolve-memory-dir.sh"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL + 1)); echo "NG: $1"; }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (expected=$3 actual=$2)"; fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-memory-ghq.XXXXXX")" || exit 1
TMP="$(cd "$TMP" && pwd -P)" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
HOME_DIR="$TMP/home"
GIT_CONFIG="$TMP/gitconfig"
mkdir -p "$HOME_DIR"
printf '' >"$GIT_CONFIG"

run_resolver() {
  HOME="$HOME_DIR" GIT_CONFIG_GLOBAL="$GIT_CONFIG" GIT_CONFIG_SYSTEM=/dev/null \
    AGENT_MEMORY_DIR="${AGENT_MEMORY_DIR:-}" GHQ_ROOT="${GHQ_ROOT:-}" \
    bash "$HELPER"
}

AGENT_MEMORY_DIR="$TMP/explicit" GHQ_ROOT="$TMP/ignored"
expect "explicit path wins" "$(run_resolver)" "$TMP/explicit"
unset AGENT_MEMORY_DIR GHQ_ROOT

GHQ_ROOT="$TMP/env-root"
expect "GHQ_ROOT wins over git config" "$(run_resolver)" \
  "$TMP/env-root/github.com/shishi/agent-memory"
unset GHQ_ROOT

printf '[ghq]\n\troot = %s\n' "$TMP/config-root" >"$GIT_CONFIG"
expect "global ghq.root is used" "$(run_resolver)" \
  "$TMP/config-root/github.com/shishi/agent-memory"

printf '' >"$GIT_CONFIG"
expect "missing configuration uses the documented default" "$(run_resolver)" \
  "$HOME_DIR/dev/src/github.com/shishi/agent-memory"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
