#!/usr/bin/env bash
# 出力ゲートの Claude Code 側の切り替えと、mod を使えないセッション (Desktop の WSL セッション) の代わりの入口。
#
#   output-gate-claude.sh enable | disable   このマシンで出力ゲートを使うか (利用者が使う切り替え)
#   output-gate-claude.sh display            MessageDisplay hook (標準入力に hook の JSON)
#   output-gate-claude.sh prompt             UserPromptSubmit hook
#
# 使うかの正本は、Git で追跡しないマシンごとの印 ($XDG_STATE_HOME/output-gate/claude-enabled)。mod も同じ印を見る。
# hook は無効のマシンでは何もしない。MessageDisplay は表示する行ごとに呼ばれるため、mod が動いているセッション
# (mod がモデルへの要求ごとに claude-mod/<session_id> を書く) では Python を起動せずに終える。
# UserPromptSubmit は毎回本体を動かし、mod の印を消し、訂正版の受け渡しと古い状態の掃除をする。処理の本体は lib/output-gate-claude.py。
set -u

hook_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/output-gate"
flag="$state_root/claude-enabled"

case "${1:-}" in
  enable)
    mkdir -p "$state_root" && : >"$flag" || { echo "$flag を書けない。" >&2; exit 1; }
    echo "出力ゲートを有効にした。次のターンから、回答を表示する前に検査する。"
    exit 0 ;;
  disable)
    rm -f -- "$flag" || { echo "$flag を消せない。" >&2; exit 1; }
    echo "出力ゲートを無効にした。"
    exit 0 ;;
  display|prompt) ;;
  *)
    echo "usage: output-gate-claude.sh enable|disable|display|prompt" >&2
    exit 2 ;;
esac

[ -e "$flag" ] || exit 0
[ "${AGENT_DELEGATED_SESSION:-}" = 1 ] && exit 0
input=$(cat)
# 早い経路: 回答を mod に任せるか (<message_id>.how が mod か) をシェルだけで決めて終える。mod の印は利用者の
# 入力のたびに本体が消すため、あれば mod が今のターンで動いている。扱いは回答の最初に動いた呼び出しが決めて
# 変えない: 任せた回答は途中で印が消えても終え、本体が貯め始めた回答 (hold) は途中で印が現れても本体に任せる。
# 扱いを作れなかった・読めなかった (書きかけを含む) ときや、session_id・message_id を読めなければ本体に任せる
# (本体も同じ判定をする)。
if [ "$1" = display ] &&
  [[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9._-]{1,128})\" ]]; then
  display_dir="$state_root/claude-display/${BASH_REMATCH[1]}"
  mod_marker="$state_root/claude-mod/${BASH_REMATCH[1]}"
  if [[ $input =~ \"message_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9._-]{1,128})\" ]]; then
    how="$display_dir/${BASH_REMATCH[1]}.how"
    if [ ! -e "$how" ] && [ -e "$mod_marker" ]; then
      # noclobber で、並んで動く呼び出しのうち作れた一つだけが決める。
      mkdir -p "$display_dir" && (set -C; printf mod >"$how") 2>/dev/null && exit 0
    fi
    [ "$(cat "$how" 2>/dev/null)" = mod ] && exit 0
  fi
fi
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -I -c '' >/dev/null 2>&1; then
    printf '%s' "$input" | "$candidate" -I "$hook_dir/lib/output-gate-claude.py" "$1"
    exit 0
  fi
done
exit 0
