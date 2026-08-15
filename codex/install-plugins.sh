#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v codex >/dev/null 2>&1; then
  echo "install-plugins: Codex CLI not found; skipping plugin reconciliation" >&2
  exit 0
fi

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
  echo "install-plugins: Python 3.11 or newer is required" >&2
  exit 1
fi

exec "$PYTHON" "$SCRIPT_DIR/install_plugins.py" "$@"
