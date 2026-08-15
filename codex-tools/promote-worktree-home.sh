#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

supports_python_311() {
  "$1" -c 'import sys; raise SystemExit(sys.version_info < (3, 11))' \
    >/dev/null 2>&1
}

PYTHON=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && \
      supports_python_311 "$candidate"; then
    PYTHON="$candidate"
    break
  fi
done

if [ -z "$PYTHON" ]; then
  echo "promote-worktree-home: Python 3.11 or newer is required" >&2
  exit 1
fi

exec "$PYTHON" "$SCRIPT_DIR/promote_worktree_home.py" "$@"
