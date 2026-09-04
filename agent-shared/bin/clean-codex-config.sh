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

/^[[:space:]]*\[(marketplaces\.openai-bundled|marketplaces\.openai-primary-runtime|mcp_servers\.node_repl(\..*)?|mcp_servers\.cua_repl)\][[:space:]]*$/ {
  skip_table = 1
  next
}

/^[[:space:]]*\[/ {
  skip_table = 0
}

skip_table {
  next
}

/^[[:space:]]*(notify|NODE_REPL_TRUSTED_BROWSER_CLIENT_SHA256S)[[:space:]]*=/ {
  next
}

{
  emit($0)
}
'
