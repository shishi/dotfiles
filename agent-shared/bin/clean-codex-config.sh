#!/usr/bin/env bash
set -eu

# プロジェクトと hook の信頼の表は、マシンの絶対パスを鍵にするマシンごとの状態なので追跡しない。
# Codex が実際に読む設定 (CODEX_HOME の config.toml) を clean するときだけ、その表をマシンに控える。
# smudge-codex-config.sh が checkout のたびに控えを書き戻す。控えは clean が走ったときに更新されるので、
# Codex が表を足した直後に clean を通らない書き直し (reset --hard など) をすると、その追加分は失われる。
store="${XDG_STATE_HOME:-$HOME/.local/state}/codex-config/trust.toml"
live_dir=$(cd "${CODEX_HOME:-$HOME/.codex}" 2>/dev/null && pwd -P) || live_dir=
snapshot=
if [ -n "$live_dir" ] && [ "$live_dir" = "$(pwd -P)/codex" ]; then
  mkdir -p "${store%/*}"
  snapshot=$(mktemp "$store.XXXXXX")
  trap 'rm -f "$snapshot"' EXIT
fi

# 控えのパスは環境変数で渡す。awk -v はバックスラッシュを解釈するので、Windows 形式のパスが崩れる。
snapshot="$snapshot" awk '
# 空行は次の行が来るまで保留し、連続する空行と末尾の空行を出さない。
function emit(line) {
  if (line ~ /^[[:space:]]*$/) {
    if (printed) pending_blank = 1
    return
  }
  if (pending_blank) print ""
  print line
  pending_blank = 0
  printed = 1
}

/^[[:space:]]*\[/ {
  in_table = 1
  in_features = ($0 ~ /^[[:space:]]*\[features\][[:space:]]*(#.*)?$/)
  keep_table = ($0 ~ /^[[:space:]]*\[(projects|hooks\.state)\./)
  skip_table = keep_table || ($0 ~ /^[[:space:]]*\[(tui\.model_availability_nux|marketplaces\.openai-bundled|marketplaces\.openai-primary-runtime|mcp_servers\.node_repl(\..*)?|mcp_servers\.cua_repl)\][[:space:]]*$/)
}

skip_table {
  if (keep_table && ENVIRON["snapshot"] != "") print > ENVIRON["snapshot"]
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

if [ -n "$snapshot" ]; then
  mv -f "$snapshot" "$store"
fi
