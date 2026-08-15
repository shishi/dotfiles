#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SETUP="${REPO_ROOT}/setup.sh"

grep -qF 'bash "${DOTDIR}/codex-tools/setup-home-links.sh" "${DOTDIR}" || exit $?' "$SETUP"
grep -qF 'bash "${DOTDIR}/codex-tools/install-plugins.sh" || exit $?' "$SETUP"

if grep -A2 -F 'codex-tools/install-plugins.sh' "$SETUP" | grep -q 'continuing'; then
  echo "setup integration still swallows Codex plugin failure" >&2
  exit 1
fi
