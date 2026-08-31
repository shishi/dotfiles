#!/usr/bin/env bash
# Record and restore the exact set of GitHub-managed Herdr plugins without a plugin manager.
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || exit 1
DOTFILES="$(cd "$SCRIPT_DIR/../.." && pwd -P)" || exit 1
LOCK_FILE="$DOTFILES/herdr/plugins.lock"

run_herdr() {
  if [ -n "${HERDR_BIN_PATH:-}" ]; then
    "$HERDR_BIN_PATH" "$@"
  elif command -v herdr.exe >/dev/null 2>&1; then
    command herdr.exe "$@"
  else
    command herdr "$@"
  fi
}

installed_plugins() {
  run_herdr plugin list --json | jq -r '
    def required($name):
      if . == null or . == "" then error("missing " + $name) else . end;

    (.result.plugins // .) as $plugins
    | if ($plugins | type) != "array"
      then error("plugin list did not return an array")
      else $plugins
      end
    | map(
        select(.source.kind == "github" and .plugin_id != "herdr-lazy")
        | (.source.owner | required("source.owner")) as $owner
        | (.source.repo | required("source.repo")) as $repo
        | (.source.subdir // "") as $subdir
        | (.source.resolved_commit | required("source.resolved_commit")) as $commit
        | "\($owner)/\($repo)\(if $subdir == "" then "" else "/" + $subdir end)@\($commit)"
      )
    | sort
    | unique[]
  '
}

record_plugins() {
  local installed tmp
  installed="$(installed_plugins)" || return 1
  tmp="$(mktemp "$LOCK_FILE.tmp.XXXXXX")" || return 1
  trap 'rm -f "$tmp"' HUP INT TERM

  {
    echo "# GitHub-managed Herdr plugins recorded after successful install/uninstall."
    echo "# Each owner/repo[/subdir]@commit is restored exactly by setup.sh."
    echo
    [ -z "$installed" ] || printf '%s\n' "$installed"
  } >"$tmp" || {
    rm -f "$tmp"
    trap - HUP INT TERM
    return 1
  }

  mv "$tmp" "$LOCK_FILE" || {
    rm -f "$tmp"
    trap - HUP INT TERM
    return 1
  }
  trap - HUP INT TERM
}

restore_plugins() {
  local installed entry spec commit
  [ -f "$LOCK_FILE" ] || return 0
  installed="$(installed_plugins)" || return 1

  while IFS= read -r entry || [ -n "$entry" ]; do
    case "$entry" in '' | \#*) continue ;; esac
    spec="${entry%@*}"
    commit="${entry##*@}"
    if [ "$spec" = "$entry" ] || [ -z "$spec" ] || [ -z "$commit" ]; then
      echo "herdr plugins: invalid lock entry: $entry" >&2
      return 1
    fi
    if printf '%s\n' "$installed" | grep -Fqx "$entry"; then
      continue
    fi
    echo "herdr plugins: installing $entry"
    run_herdr plugin install "$spec" --ref "$commit" --yes || return 1
  done <"$LOCK_FILE"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "herdr plugins: jq not found" >&2
  exit 1
fi
if [ -z "${HERDR_BIN_PATH:-}" ] \
  && ! command -v herdr.exe >/dev/null 2>&1 \
  && ! command -v herdr >/dev/null 2>&1; then
  echo "herdr plugins: herdr not found" >&2
  exit 1
fi

case "${1:-}" in
  record) record_plugins ;;
  restore) restore_plugins ;;
  *) echo "usage: ${0##*/} {record|restore}" >&2; exit 2 ;;
esac
