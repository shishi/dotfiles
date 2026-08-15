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

# The helper derives dotfiles root from its own location, so it works without
# accepting a fixture path or touching the real home directory.
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
FIXTURE_ROOT="${TEST_ROOT}/dotfiles"
FIXTURE_HELPER="${FIXTURE_ROOT}/codex-tools/setup-home-links.sh"
FIXTURE_HOME="${TEST_ROOT}/home"
mkdir -p "${FIXTURE_ROOT}/codex/skills" "${FIXTURE_ROOT}/codex-tools" \
  "${FIXTURE_HOME}"
cp "${REPO_ROOT}/codex-tools/setup-home-links.sh" "$FIXTURE_HELPER"

HOME="$FIXTURE_HOME" bash "$FIXTURE_HELPER"

[ "$(cd "${FIXTURE_HOME}/.codex" && pwd -P)" = "$(cd "${FIXTURE_ROOT}/codex" && pwd -P)" ]
[ "$(cd "${FIXTURE_HOME}/.agents/skills" && pwd -P)" = "$(cd "${FIXTURE_ROOT}/codex/skills" && pwd -P)" ]
