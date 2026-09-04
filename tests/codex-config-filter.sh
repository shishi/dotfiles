#!/usr/bin/env bash
set -eu

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CLEANER="$REPO/agent-shared/bin/clean-codex-config.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/codex-config-filter.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

cat >"$TMP/input.toml" <<'EOF'
model = "gpt-5.6-sol"

notify = ["/Applications/ChatGPT.app/notify", "turn-ended"]

[features]
hooks = true

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
