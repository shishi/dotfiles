#!/usr/bin/env bash
# claude/install-plugins.sh の marketplace 解決を検査する。
#
# settings.json の extraKnownMarketplaces には source が "github" のものと
# "directory" のものが混在する。directory のものは特定マシンのローカル path を
# 指すので、他のマシンでは解決しようがない。install-plugins.sh がこれを
# 「MARKETPLACE_REPO に追加せよ」と警告すると、その指示に従っても直らない
# (MARKETPLACE_REPO は owner/repo しか持てない)。障害対応中に読まれる文言なので、
# 実行不能な指示を出さないことと、代わりに出す skip 行の内容をここで固定する。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${REPO}/claude/install-plugins.sh"
PASS=0
FAIL=0
ok() {
  PASS=$((PASS + 1))
  echo "ok: $1"
}
ng() {
  FAIL=$((FAIL + 1))
  echo "NG: $1"
}

command -v jq >/dev/null 2>&1 || {
  echo "fatal: jq not found; this test cannot run" >&2
  exit 1
}

# mktemp -d が失敗しても set -e が無いので実行は続く。root が空のまま先へ進むと
# "${root}/bin/claude" は /bin/claude になり、PATH 上位に「成功したふりをして
# 何もしない claude」を永続的に残す。空を掴んだ時点で落とす。
require_root() {
  [ -n "$1" ] || {
    echo "fatal: mktemp -d produced no directory; refusing to write to /" >&2
    exit 1
  }
}

# claude CLI を呼び出し記録用の stub に差し替える。実際の install はしない。
make_stub() {
  local root="$1"
  require_root "$root"
  mkdir -p "${root}/bin"
  cat >"${root}/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${CLAUDE_STUB_LOG}"
exit 0
STUB
  chmod +x "${root}/bin/claude"
}

# $2 は enabledPlugins、$3 は extraKnownMarketplaces の JSON 断片。
make_config() {
  local root="$1" enabled="$2" marketplaces="$3"
  require_root "$root"
  mkdir -p "${root}/config/plugins"
  jq -n --argjson e "$enabled" --argjson m "$marketplaces" \
    '{enabledPlugins: $e, extraKnownMarketplaces: $m}' \
    >"${root}/config/settings.json"
  echo '{}' >"${root}/config/plugins/known_marketplaces.json"
  echo '{"plugins": {}}' >"${root}/config/plugins/installed_plugins.json"
}

# 「何も起きない」ことを見るアサーションは、スクリプトが冒頭で早期 exit しても
# 通ってしまう (claude / jq 不在の skip 経路など)。ループが最後まで回ったことを
# summary 行の到達で確かめ、以降のアサーションの前提を固定する。
run_script() {
  local root="$1" quiet="${2:-0}" summary="${3:-1}"
  CLAUDE_CONFIG_DIR="${root}/config" \
    CLAUDE_STUB_LOG="${root}/claude-args.log" \
    INSTALL_PLUGINS_QUIET="$quiet" \
    INSTALL_PLUGINS_SUMMARY="$summary" \
    PATH="${root}/bin:$PATH" \
    bash "$SCRIPT" >"${root}/out.log" 2>&1
  echo "$?" >"${root}/exit"
  if [ "$quiet" != 1 ] && [ "$summary" != 0 ]; then
    grep -q 'install-plugins: done' "${root}/out.log" \
      || ng "script never reached the summary line (early exit); later assertions are meaningless"
  fi
}

trap 'rm -rf "${T1:-}" "${T2:-}" "${T3:-}" "${T4:-}" "${T5:-}" "${T6:-}" "${T7:-}" "${T8:-}" "${T9:-}"' EXIT

# 1. directory marketplace の path がこのマシンに無い場合。
#    このマシン用の plugin ではないので、WARN ではなく通常ログ 1 行にして飛ばす。
#    MARKETPLACE_REPO へ追加せよという実行不能な指示を出さない。unresolved にも数えない
#    (unresolved は「対応表に足せば直る」ものを指すため)。
T1="$(mktemp -d)"
make_stub "$T1"
make_config "$T1" \
  '{"vue-lsp@teachme-web-lsp": true}' \
  '{"teachme-web-lsp": {"source": {"source": "directory", "path": "/nonexistent/machine/local/marketplace"}}}'
run_script "$T1"
if ! grep -q 'MARKETPLACE_REPO' "${T1}/out.log"; then
  ok "a directory marketplace absent from this machine does not suggest MARKETPLACE_REPO"
else
  ng "an unreachable directory marketplace was reported as fixable via MARKETPLACE_REPO"
fi
if grep -q 'unresolved: 0' "${T1}/out.log"; then
  ok "a directory marketplace absent from this machine is not counted as unresolved"
else
  ng "a directory marketplace absent from this machine was counted as unresolved"
fi
# skip は「なぜこの plugin が入っていないのか」を知る唯一の手掛かりなので、
# 出力そのものを固定する。出さなくなっても他のアサーションは通ってしまう。
if grep -q 'skipped: 1' "${T1}/out.log"; then
  ok "an absent directory marketplace is counted as skipped"
else
  ng "an absent directory marketplace was not counted as skipped"
fi
if grep -qF '/nonexistent/machine/local/marketplace, which does not exist on this machine' \
  "${T1}/out.log"; then
  ok "the skip line names the path that is missing"
else
  ng "the skip line does not tell the reader which path was missing"
fi
if [ ! -s "${T1}/claude-args.log" ]; then
  ok "no claude subcommand runs for a marketplace that cannot exist here"
else
  ng "claude was invoked for a marketplace whose directory is absent"
fi
if [ "$(cat "${T1}/exit")" = "0" ]; then
  ok "skipping an absent directory marketplace keeps the exit status successful"
else
  ng "skipping an absent directory marketplace made the script fail"
fi

# 2. directory marketplace の path がこのマシンに在る場合 (会社 mac など)。
#    ここでは今まで通り install する。path をそのまま marketplace の出所として
#    渡す (owner/repo 形式には変換できないため)。
T2="$(mktemp -d)"
make_stub "$T2"
mkdir -p "${T2}/lsp-marketplace"
make_config "$T2" \
  '{"vue-lsp@teachme-web-lsp": true}' \
  "$(jq -n --arg p "${T2}/lsp-marketplace" \
    '{"teachme-web-lsp": {source: {source: "directory", path: $p}}}')"
run_script "$T2"
# path は settings.json から読み戻す。Windows の jq は --arg に渡した MSYS path を
# ネイティブ表記へ変換するので、シェル側の "${T2}/..." と綴りが一致しない。
declared_path="$(jq -r '.extraKnownMarketplaces["teachme-web-lsp"].source.path' \
  "${T2}/config/settings.json" | tr -d '\r')"
if grep -qF "plugin marketplace add ${declared_path}" "${T2}/claude-args.log" 2>/dev/null; then
  ok "a directory marketplace present on this machine is added by its path"
else
  ng "a present directory marketplace was not added by its path"
fi
if grep -q 'plugin install vue-lsp@teachme-web-lsp' "${T2}/claude-args.log" 2>/dev/null; then
  ok "a plugin from a present directory marketplace is installed"
else
  ng "a plugin from a present directory marketplace was not installed"
fi

# 3. どこにも定義の無い marketplace は今まで通り警告する。ここは対応表に
#    1 行足せば直るので、その指示は正しい。
T3="$(mktemp -d)"
make_stub "$T3"
make_config "$T3" '{"some-plugin@unheard-of": true}' '{}'
run_script "$T3"
if grep -q 'MARKETPLACE_REPO' "${T3}/out.log"; then
  ok "a marketplace with no definition anywhere still points at MARKETPLACE_REPO"
else
  ng "a genuinely unmapped marketplace lost its actionable warning"
fi
if grep -q 'unresolved: 1' "${T3}/out.log"; then
  ok "a genuinely unmapped marketplace is still counted as unresolved"
else
  ng "a genuinely unmapped marketplace was not counted as unresolved"
fi

# 4. MARKETPLACE_REPO に載る github marketplace は従来通り解決する。
T4="$(mktemp -d)"
make_stub "$T4"
make_config "$T4" '{"superpowers@superpowers-marketplace": true}' '{}'
run_script "$T4"
if grep -q 'plugin marketplace add obra/superpowers-marketplace' "${T4}/claude-args.log" 2>/dev/null; then
  ok "a github marketplace in MARKETPLACE_REPO is still resolved"
else
  ng "a github marketplace in MARKETPLACE_REPO stopped resolving"
fi

# 5. directory source なのに path が無い/空。手編集や上流のスキーマ変更で起きうる。
#    path 名を空欄にしたまま「存在しない」と言うと、path が空文字なのか
#    メッセージ生成が壊れているのか読み手に区別がつかない。別の文面で言う。
T5="$(mktemp -d)"
make_stub "$T5"
make_config "$T5" \
  '{"vue-lsp@teachme-web-lsp": true}' \
  '{"teachme-web-lsp": {"source": {"source": "directory"}}}'
run_script "$T5"
if grep -q 'no path in settings.json' "${T5}/out.log"; then
  ok "a directory marketplace without a path says so instead of naming an empty path"
else
  ng "a directory marketplace without a path produces a message with a blank path"
fi
if grep -q 'skipped: 1' "${T5}/out.log"; then
  ok "a directory marketplace without a path is counted as skipped"
else
  ng "a directory marketplace without a path was not counted as skipped"
fi
if [ ! -s "${T5}/claude-args.log" ]; then
  ok "no claude subcommand runs for a directory marketplace without a path"
else
  ng "claude was invoked for a directory marketplace without a path"
fi

# 6. Herdr が同じ desired state を再確認する場合は、正常な skip と summary を黙らせる。
T6="$(mktemp -d)"
make_stub "$T6"
make_config "$T6" \
  '{"vue-lsp@teachme-web-lsp": true}' \
  '{"teachme-web-lsp": {"source": {"source": "directory", "path": "/nonexistent/machine/local/marketplace"}}}'
run_script "$T6" 1
if [ ! -s "${T6}/out.log" ] && [ "$(cat "${T6}/exit")" = 0 ]; then
  ok "quiet reconciliation suppresses normal skip and summary logs"
else
  ng "quiet reconciliation emitted normal logs or changed the successful exit status"
fi

# 7. quiet は障害を隠さない。plugin install 失敗と非 0 status は呼び出し元へ返す。
T7="$(mktemp -d)"
make_stub "$T7"
cat >"${T7}/bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${CLAUDE_STUB_LOG}"
case "$*" in
  'plugin install '*) exit 1 ;;
esac
exit 0
EOF
chmod +x "${T7}/bin/claude"
make_config "$T7" '{"superpowers@superpowers-marketplace": true}' '{}'
run_script "$T7" 1
if grep -q 'WARN failed to install superpowers@superpowers-marketplace' "${T7}/out.log" \
  && grep -q 'failed: 1' "${T7}/out.log" \
  && [ "$(cat "${T7}/exit")" != 0 ]; then
  ok "quiet reconciliation keeps failure details and status"
else
  ng "quiet reconciliation hid a plugin installation failure"
fi

# 8. setup.sh が親 result を出す場合、通常 detail は残して子 summary だけを消す。
T8="$(mktemp -d)"
make_stub "$T8"
make_config "$T8" \
  '{"vue-lsp@teachme-web-lsp": true}' \
  '{"teachme-web-lsp": {"source": {"source": "directory", "path": "/nonexistent/machine/local/marketplace"}}}'
run_script "$T8" 0 0
if grep -q 'install-plugins: skip vue-lsp@teachme-web-lsp' "${T8}/out.log" \
  && ! grep -q 'install-plugins: done' "${T8}/out.log" \
  && [ "$(cat "${T8}/exit")" = 0 ]; then
  ok "embedded reconciliation keeps detail and suppresses its summary"
else
  ng "embedded reconciliation hid detail or emitted a duplicate summary"
fi

# 9. summary を親へ委ねても、失敗 detail と非 0 status は維持する。
T9="$(mktemp -d)"
make_stub "$T9"
cat >"${T9}/bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${CLAUDE_STUB_LOG}"
case "$*" in
  'plugin install '*) exit 1 ;;
esac
exit 0
EOF
chmod +x "${T9}/bin/claude"
make_config "$T9" '{"superpowers@superpowers-marketplace": true}' '{}'
run_script "$T9" 0 0
if grep -q 'WARN failed to install superpowers@superpowers-marketplace' "${T9}/out.log" \
  && ! grep -q 'install-plugins: done' "${T9}/out.log" \
  && [ "$(cat "${T9}/exit")" != 0 ]; then
  ok "embedded reconciliation keeps failure detail and status"
else
  ng "embedded reconciliation hid a failure or emitted a duplicate summary"
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
