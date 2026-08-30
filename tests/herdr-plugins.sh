#!/usr/bin/env bash
# Herdr の GitHub plugin snapshot と固定 commit 復元の契約を検証する。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$REPO/agents/bin/herdr-plugins.sh"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL + 1)); echo "NG: $1"; }
assert() { local description="$1"; shift; if "$@"; then ok "$description"; else ng "$description"; fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/herdr-plugins.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

DOTFILES="$TMP/dotfiles"
mkdir -p "$DOTFILES/agents/bin" "$DOTFILES/herdr"
cp "$SCRIPT" "$DOTFILES/agents/bin/herdr-plugins.sh"

cat >"$TMP/herdr" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "plugin list --json")
    [ "${HERDR_PLUGIN_LIST_FAIL:-0}" = 0 ] || exit 1
    cat "$HERDR_PLUGIN_FIXTURE"
    ;;
  "plugin install "*) printf '%s\n' "$*" >>"$HERDR_PLUGIN_CALLS" ;;
  *) echo "unexpected herdr call: $*" >&2; exit 2 ;;
esac
EOF
chmod +x "$TMP/herdr"

cat >"$TMP/installed.json" <<'EOF'
{
  "id": "cli:plugin",
  "result": {
    "plugins": [
      {
        "plugin_id": "beta",
        "source": {
          "kind": "github",
          "owner": "zeta",
          "repo": "beta",
          "resolved_commit": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        }
      },
      {
        "plugin_id": "alpha",
        "source": {
          "kind": "github",
          "owner": "alpha",
          "repo": "plugins",
          "subdir": "tools/alpha",
          "resolved_commit": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        }
      },
      {
        "plugin_id": "local-only",
        "source": { "kind": "local" }
      },
      {
        "plugin_id": "herdr-lazy",
        "source": {
          "kind": "github",
          "owner": "natori-hrj",
          "repo": "herdr-lazy",
          "resolved_commit": "dddddddddddddddddddddddddddddddddddddddd"
        }
      }
    ],
    "type": "plugin_list"
  }
}
EOF

export HERDR_BIN_PATH="$TMP/herdr"
export HERDR_PLUGIN_FIXTURE="$TMP/installed.json"
export HERDR_PLUGIN_CALLS="$TMP/calls"

if bash "$DOTFILES/agents/bin/herdr-plugins.sh" record; then
  actual="$(grep -v '^#' "$DOTFILES/herdr/plugins.lock" | sed '/^[[:space:]]*$/d')"
  expected="$(printf '%s\n' \
    'alpha/plugins/tools/alpha@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
    'zeta/beta@bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')"
  assert "record writes managed GitHub plugins and excludes the replaced manager" \
    test "$actual" = "$expected"
else
  ng "record writes managed GitHub plugins and excludes the replaced manager"
fi

cat >"$DOTFILES/herdr/plugins.lock" <<'EOF'
alpha/plugins/tools/alpha@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
missing/plugin@cccccccccccccccccccccccccccccccccccccccc
EOF
: >"$HERDR_PLUGIN_CALLS"

if bash "$DOTFILES/agents/bin/herdr-plugins.sh" restore; then
  assert "restore installs only missing commits" \
    test "$(cat "$HERDR_PLUGIN_CALLS")" = \
      "plugin install missing/plugin --ref cccccccccccccccccccccccccccccccccccccccc --yes"
else
  ng "restore installs only missing commits"
fi

printf 'keep/me@eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\n' \
  >"$DOTFILES/herdr/plugins.lock"
export HERDR_PLUGIN_LIST_FAIL=1
if bash "$DOTFILES/agents/bin/herdr-plugins.sh" record >/dev/null 2>&1; then
  ng "record preserves the lock when Herdr listing fails"
elif test "$(cat "$DOTFILES/herdr/plugins.lock")" = \
  'keep/me@eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'; then
  ok "record preserves the lock when Herdr listing fails"
else
  ng "record preserves the lock when Herdr listing fails"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
