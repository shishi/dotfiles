#!/usr/bin/env bash
set -eu

shared_dir=$(cd -P -- "$(dirname "$0")/.." && pwd -P)
mod="$shared_dir/claude-mods/kata-research"
if [ ! -f "$mod/.claude-plugin/plugin.json" ]; then
  echo 'Claude Code の調査制御のファイルが見つかりません。' >&2
  exit 1
fi

state_dir=$(mktemp -d "${TMPDIR:-/tmp}/kata-claude.XXXXXX")
cleanup() {
  for marker in "$state_dir"/*; do
    [ -f "$marker" ] && rm -- "$marker"
  done
  rmdir -- "$state_dir"
}
trap cleanup EXIT

KATA_RESEARCH_CLAUDE_STATE="$state_dir" \
  KATA_RESEARCH_CLAUDE_PUBLIC_HTTPS_READER="$shared_dir/bin/kata-public-https.py" \
  command claude --plugin-dir "$mod" "$@" <&0 &
child=$!
stop() {
  kill -TERM "$child" 2>/dev/null || :
  wait "$child" || :
  exit 130
}
trap stop INT TERM HUP
wait "$child"
