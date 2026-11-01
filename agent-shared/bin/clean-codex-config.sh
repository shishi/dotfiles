#!/usr/bin/env bash
set -eu

awk '
function emit(line) {
  if (line ~ /^[[:space:]]*$/) {
    if (!last_was_blank) print line
    last_was_blank = 1
    return
  }
  print line
  last_was_blank = 0
}

/^[[:space:]]*\[(tui\.model_availability_nux|marketplaces\.openai-bundled|marketplaces\.openai-primary-runtime|mcp_servers\.node_repl(\..*)?|mcp_servers\.cua_repl)\][[:space:]]*$/ {
  skip_table = 1
  next
}

/^[[:space:]]*\[/ {
  skip_table = 0
  in_features = ($0 ~ /^[[:space:]]*\[features\][[:space:]]*(#.*)?$/)
  in_table = 1
}

skip_table {
  next
}

/^[[:space:]]*(notify|NODE_REPL_TRUSTED_BROWSER_CLIENT_SHA256S)[[:space:]]*=/ {
  next
}

# 出力ゲートがマシンごとに書く行 (output-gate-codex-config.py)。中継を有効にしたマシンだけの設定のため追跡しない。
!in_table && /^[[:space:]]*openai_base_url[[:space:]]*=/ {
  next
}

in_features && /^[[:space:]]*(token_budget|context_management|output_token_replay|enable_request_compression)[[:space:]]*=/ {
  next
}

{
  emit($0)
}
'
