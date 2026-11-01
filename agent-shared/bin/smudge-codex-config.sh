#!/usr/bin/env bash
# Git の smudge フィルター (codex/config.toml): 出力ゲートを有効にしたマシンでは、作業コピーへ書き出す
# 内容に中継の行を戻す。clean フィルター (clean-codex-config.sh) が Git から除く行と同じもの。
# Python が無ければ入力をそのまま出す。
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -I -c '' >/dev/null 2>&1; then
    exec "$candidate" -I "$script_dir/output-gate-codex-config.py" smudge
  fi
done
exec cat
