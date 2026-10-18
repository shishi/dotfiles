#!/usr/bin/env bash
set -eu
if ! command -v python3 >/dev/null 2>&1; then
  echo 'codex-verified: python3 が必要です。回答は公開していません。' >&2
  exit 1
fi
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/codex-verified.py" "$@"
