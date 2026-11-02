#!/usr/bin/env bash
set -eu

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CLEANER="$REPO/agent-shared/bin/clean-codex-config.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/codex-config-filter.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
# 稼働中の checkout から実行しても、マシンの控えに触れない。
export XDG_STATE_HOME="$TMP/state" CODEX_HOME="$TMP/no-live-config"

cat >"$TMP/input.toml" <<'EOF'
model = "gpt-5.6-sol"

notify = ["/Applications/ChatGPT.app/notify", "turn-ended"]
openai_base_url = "http://127.0.0.1:18800/backend-api/codex"

[features]
token_budget = false
context_management = false
output_token_replay = false
enable_request_compression = false
hooks = true

[tui]
status_line = ["model-with-reasoning"]

[tui.model_availability_nux]
"gpt-6.1-sol" = 4
gpt-6-astra = 3

[shell_environment_policy.set]
MCP_TOOL_TIMEOUT = "120000"
NODE_REPL_TRUSTED_BROWSER_CLIENT_SHA256S = "machine-hash"

[marketplaces.openai-bundled]
last_updated = "2026-08-21T09:37:57Z"
source_type = "local"
source = 'C:\Users\shishi\.codex\bundled'

[marketplaces.openai-primary-runtime]
source_type = "local"
source = "/home/shishi/.cache/codex-runtime"

[plugins."computer-use@openai-bundled"]
enabled = true

[mcp_servers.cloudflare-api]
url = "https://mcp.cloudflare.com/mcp"

[mcp_servers.node_repl]
command = "/Applications/ChatGPT.app/node_repl"

[mcp_servers.node_repl.env]
CODEX_HOME = "/Users/shishi/.codex"

[mcp_servers.cua_repl]
command = "/Applications/ChatGPT.app/ChatGPT"

[memories]
generate_memories = false
EOF

cat >"$TMP/expected.toml" <<'EOF'
model = "gpt-5.6-sol"

[features]
hooks = true

[tui]
status_line = ["model-with-reasoning"]

[shell_environment_policy.set]
MCP_TOOL_TIMEOUT = "120000"

[plugins."computer-use@openai-bundled"]
enabled = true

[mcp_servers.cloudflare-api]
url = "https://mcp.cloudflare.com/mcp"

[memories]
generate_memories = false
EOF

bash "$CLEANER" <"$TMP/input.toml" >"$TMP/actual.toml"

if cmp -s "$TMP/expected.toml" "$TMP/actual.toml"; then
  echo "ok: machine-local Codex state is excluded from the Git view"
else
  diff -u "$TMP/expected.toml" "$TMP/actual.toml"
  exit 1
fi

# Exercise git add, including a later counter update mixed with a real setting.
mkdir -p "$TMP/repo/codex"
git -C "$TMP/repo" init -q
printf 'codex/config.toml filter=codex-config\n' >"$TMP/repo/.gitattributes"
git -C "$TMP/repo" config filter.codex-config.clean "bash '$CLEANER'"
git -C "$TMP/repo" config filter.codex-config.smudge cat
git -C "$TMP/repo" config filter.codex-config.required true
cp "$TMP/input.toml" "$TMP/repo/codex/config.toml"
git -C "$TMP/repo" add codex/config.toml
git -C "$TMP/repo" show :codex/config.toml >"$TMP/staged.toml"
cmp "$TMP/expected.toml" "$TMP/staged.toml"
cmp "$TMP/input.toml" "$TMP/repo/codex/config.toml"
sed -e 's/"gpt-6.1-sol" = 4/"gpt-6.1-sol" = 5/' -e 's/model = "gpt-5.6-sol"/model = "gpt-6-astra"/' "$TMP/input.toml" >"$TMP/updated.toml"
sed 's/model = "gpt-5.6-sol"/model = "gpt-6-astra"/' "$TMP/expected.toml" >"$TMP/updated-expected.toml"
cp "$TMP/updated.toml" "$TMP/repo/codex/config.toml"
git -C "$TMP/repo" add codex/config.toml
git -C "$TMP/repo" show :codex/config.toml >"$TMP/staged.toml"
cmp "$TMP/updated-expected.toml" "$TMP/staged.toml"
cmp "$TMP/updated.toml" "$TMP/repo/codex/config.toml"
echo "ok: git add excludes counters, stages settings, and preserves local state"

# checkout が作業コピーを書き直しても、出力ゲートを有効にしたマシンでは中継の行が戻る。
SMUDGER="$REPO/agent-shared/bin/smudge-codex-config.sh"
git -C "$TMP/repo" config filter.codex-config.smudge "bash '$SMUDGER'"
git -C "$TMP/repo" -c user.name=t -c user.email=t@example.invalid commit -q -m config
export XDG_STATE_HOME="$TMP/state"
mkdir -p "$XDG_STATE_HOME/output-gate"
printf '{"enabled": true, "port": 18800}\n' >"$XDG_STATE_HOME/output-gate/codex.json"
rm "$TMP/repo/codex/config.toml"
git -C "$TMP/repo" checkout -- codex/config.toml
grep -q '^openai_base_url = "http://127.0.0.1:18800/backend-api/codex"' "$TMP/repo/codex/config.toml"
grep -q '^enable_request_compression = false' "$TMP/repo/codex/config.toml"
[ -z "$(git -C "$TMP/repo" status --porcelain codex/config.toml)" ]
printf '{"enabled": false, "port": 18800}\n' >"$XDG_STATE_HOME/output-gate/codex.json"
rm "$TMP/repo/codex/config.toml"
git -C "$TMP/repo" checkout -- codex/config.toml
cmp "$TMP/updated-expected.toml" "$TMP/repo/codex/config.toml"
echo "ok: checkout restores the relay lines only where the output gate is enabled"

# パスを鍵にする表 (プロジェクトと hook の信頼) はマシンごとの状態なので Git に入れない。
# 稼働中の設定 (CODEX_HOME の config.toml) の表はマシンに控え、checkout で書き直しても戻す。
cat >"$TMP/trust.toml" <<'TOML'
[projects.'c:\users\example\work']
trust_level = "trusted"

[hooks.state."/home/example/.codex/hooks.json:session_start:0:0"]
trusted_hash = "sha256:00"
TOML
{ cat "$TMP/updated-expected.toml"; echo; cat "$TMP/trust.toml"; } >"$TMP/repo/codex/config.toml"
export CODEX_HOME="$TMP/repo/codex"
git -C "$TMP/repo" add codex/config.toml
git -C "$TMP/repo" show :codex/config.toml >"$TMP/staged.toml"
cmp "$TMP/updated-expected.toml" "$TMP/staged.toml"
# 別の checkout (稼働中でない設定) の clean は控えを書き換えない。
mkdir -p "$TMP/other/codex"
(cd "$TMP/other" && bash "$CLEANER" <"$TMP/updated-expected.toml" >/dev/null)
rm "$TMP/repo/codex/config.toml"
git -C "$TMP/repo" checkout -- codex/config.toml
grep -qF "[projects.'c:\users\example\work']" "$TMP/repo/codex/config.toml"
grep -qF '[hooks.state."/home/example/.codex/hooks.json:session_start:0:0"]' "$TMP/repo/codex/config.toml"
[ -z "$(git -C "$TMP/repo" status --porcelain codex/config.toml)" ]
echo "ok: path-keyed trust tables stay out of Git and survive checkout on the live config"

# 表を追跡していた版を書き出しても、入力の表と控えの表が二重にならない。
rm -rf "$XDG_STATE_HOME/codex-config"
{ cat "$TMP/updated-expected.toml"; echo; cat "$TMP/trust.toml"; } >"$TMP/repo/codex/config.toml"
git -C "$TMP/repo" -c filter.codex-config.clean=cat add codex/config.toml
git -C "$TMP/repo" -c user.name=t -c user.email=t@example.invalid commit -q -m tracked-trust
rm "$TMP/repo/codex/config.toml"
git -C "$TMP/repo" checkout -- codex/config.toml
[ "$(grep -cF "[projects.'c:\users\example\work']" "$TMP/repo/codex/config.toml")" = 1 ]
[ "$(grep -cF '[hooks.state.' "$TMP/repo/codex/config.toml")" = 1 ]
[ -s "$XDG_STATE_HOME/codex-config/trust.toml" ]
echo "ok: checking out a version that still tracks the tables does not duplicate them"

# 控えに無い表 (stash の取り出しなどで戻る、まだ控えていない信頼) は書き出しで落とさない。
printf '
[projects."/home/example/new-worktree"]
trust_level = "trusted"
' >>"$TMP/repo/codex/config.toml"
git -C "$TMP/repo" -c filter.codex-config.clean=cat add codex/config.toml
rm "$TMP/repo/codex/config.toml"
git -C "$TMP/repo" checkout -- codex/config.toml
[ "$(grep -cF '[projects."/home/example/new-worktree"]' "$TMP/repo/codex/config.toml")" = 1 ]
[ "$(grep -cF "[projects.'c:\users\example\work']" "$TMP/repo/codex/config.toml")" = 1 ]
echo "ok: tables missing from the snapshot are kept when written out"

# 移行の実経路: 表を追跡していた版 (旧フィルター) の稼働中の checkout を fast-forward で更新する。
# 更新前の検査は旧 clean、書き出しは先に置き換わった新 smudge が行う。表は残り、変更扱いにならない。
# 旧フィルターは表を素通しする (この点だけを再現する)。
mkdir -p "$TMP/up/agent-shared/bin" "$TMP/up/codex"
git -C "$TMP/up" init -q
printf 'codex/config.toml filter=codex-config\n' >"$TMP/up/.gitattributes"
for f in clean-codex-config.sh smudge-codex-config.sh; do
  printf '#!/usr/bin/env bash\nexec cat\n' >"$TMP/up/agent-shared/bin/$f"
done
{ cat "$TMP/updated-expected.toml"; echo; cat "$TMP/trust.toml"; } >"$TMP/up/codex/config.toml"
git -C "$TMP/up" -c filter.codex-config.clean=cat add -A
git -C "$TMP/up" -c user.name=t -c user.email=t@example.invalid commit -q -m old
cp "$REPO/agent-shared/bin/clean-codex-config.sh" "$REPO/agent-shared/bin/smudge-codex-config.sh" "$REPO/agent-shared/bin/output-gate-codex-config.py" "$TMP/up/agent-shared/bin/"
cp "$TMP/updated-expected.toml" "$TMP/up/codex/config.toml"
git -C "$TMP/up" -c filter.codex-config.clean=cat add -A
git -C "$TMP/up" -c user.name=t -c user.email=t@example.invalid commit -q -m new
git clone -q --no-checkout "$TMP/up" "$TMP/live"
git -C "$TMP/live" config filter.codex-config.clean "bash agent-shared/bin/clean-codex-config.sh"
git -C "$TMP/live" config filter.codex-config.smudge "[ -f agent-shared/bin/smudge-codex-config.sh ] && exec bash agent-shared/bin/smudge-codex-config.sh || exec cat"
git -C "$TMP/live" config filter.codex-config.required true
rm -rf "$XDG_STATE_HOME/codex-config"
export CODEX_HOME="$TMP/live/codex"
git -C "$TMP/live" checkout -q -B main HEAD~1
[ ! -e "$XDG_STATE_HOME/codex-config/trust.toml" ]
git -C "$TMP/live" merge -q --ff-only origin/HEAD
[ "$(grep -cF "[projects.'c:\users\example\work']" "$TMP/live/codex/config.toml")" = 1 ]
[ "$(grep -cF '[hooks.state.' "$TMP/live/codex/config.toml")" = 1 ]
[ -z "$(git -C "$TMP/live" status --porcelain)" ]
echo "ok: pulling the change into a live checkout keeps its trust tables"
