#!/usr/bin/env bash
# Git の smudge フィルター (codex/config.toml): clean フィルター (clean-codex-config.sh) が Git から
# 除くマシンごとの状態を、作業コピーへ書き出す内容に戻す。
# - 出力ゲートを有効にしたマシンでは中継の行。Python が無ければ戻さない。
# - clean が稼働中の設定から控えたプロジェクトと hook の信頼の表。
set -o pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
store="${XDG_STATE_HOME:-$HOME/.local/state}/codex-config/trust.toml"

gate_lines() {
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -I -c '' >/dev/null 2>&1; then
      "$candidate" -I "$script_dir/output-gate-codex-config.py" smudge
      return
    fi
  done
  cat
}

# 表を追跡していた版から更新するマシンには、まだ控えが無い。更新前の HEAD は表を含むので、
# そこから控えを作る (稼働中の設定のときだけ clean が控えを書く)。控えを書けなければ
# 書き出しを止め、信頼を黙って落とさない。
if [ ! -e "$store" ] && head_config=$(git show HEAD:codex/config.toml 2>/dev/null); then
  printf '%s\n' "$head_config" | bash "$script_dir/clean-codex-config.sh" >/dev/null || exit
fi

# 入力に残る表のうち控えにあるものは、控えから足すので除く (表を追跡していた版の書き出しで
# 二重にしないため)。控えに無い表 (stash などで戻る未控えの表) はそのまま残す。
drop_known_tables() {
  if [ ! -s "$store" ]; then
    cat
    return
  fi
  awk '
    FNR == NR {
      if ($0 ~ /^[[:space:]]*\[/) known[$0] = 1
      next
    }
    /^[[:space:]]*\[/ { skip = ($0 in known) }
    !skip
  ' "$store" -
}

drop_known_tables | gate_lines || exit
if [ -s "$store" ]; then
  printf '\n'
  cat "$store"
fi
