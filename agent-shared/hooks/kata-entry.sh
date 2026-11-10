#!/usr/bin/env bash
# SessionStart hook: 変更作業の入口を kata に向ける。skill の選択は description に気づくかに依存し、
# ざっくりした依頼では kata を経ずに作業を始めたり、工程の途中で工程 skill を開かずに進めたりするため、
# 入口と工程ごとの skill を確定的に差し込む。Codex にも同じ内容を渡し、両 CLI の入口をそろえる。
#
# あわせて、kata の工程 skill へ取り込んだ superpowers の上流に新しい版が出ていないかを月に一度だけ
# 確かめ、出ていれば取り込みを促す。毎回の起動で通信しないよう、確認結果を状態ファイルに残して使い回す。
set -u

cat <<'MSG'
<kata-entry>
変更作業の入口は kata skill。作業の最初に kata を開き、続けて工程 1 の kata-design を開いて目的と方式を固める。kata-design を不要と判断した場合は、省く前に根拠を示して利用者に質問する。既存の設計・計画がある仕事や圧縮後の再開では、kata の該当工程から進める。工程に入るたびに kata の工程表を確かめ、その工程の skill (kata-workspace・kata-plan・kata-build・review-gate・kata-verify・kata-finish) を開いてから進める。不具合・想定外の挙動を調べるときは investigation-discipline、テストを書くときは test-red-first を開く。
</kata-entry>
MSG

agent_shared=$(cd -P "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 0
imported=$(head -n 1 "$agent_shared/superpowers-imported-version" 2>/dev/null) || exit 0
[ -n "$imported" ] || exit 0

uid=$(id -u)
state_dir=${KATA_UPSTREAM_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-shared}
if ! mkdir -p "$state_dir" 2>/dev/null || [ ! -w "$state_dir" ]; then
  state_dir=${TMPDIR:-/tmp}/claude-$uid/kata
  mkdir -p "$state_dir" 2>/dev/null || exit 0
fi
state=$state_dir/superpowers-upstream
url=${KATA_UPSTREAM_URL:-https://github.com/obra/superpowers}
interval=$((30 * 24 * 60 * 60))
now=$(date +%s)

# 状態ファイルは「確認した時刻 上流の最新版」の 1 行。
checked=0 latest=
if [ -r "$state" ]; then
  read -r checked latest < "$state" || true
fi
case $checked in '' | *[!0-9]*) checked=0 ;; esac

if [ $((now - checked)) -ge "$interval" ]; then
  # 通信できなければ、次の起動で再び確かめるよう時刻を更新しない。利用者の Git 設定が github.com を
  # SSH へ書き換えていると鍵の確認で端末の入力を奪うため、設定を読まずに匿名の HTTPS で取得する。
  found=$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 timeout 5 git ls-remote --tags --refs "$url" 2>/dev/null |
    sed -n 's|.*refs/tags/v\{0,1\}\([0-9][0-9.]*\)$|\1|p' | sort -V | tail -n 1)
  if [ -n "$found" ]; then
    latest=$found
    printf '%s %s\n' "$now" "$latest" > "$state" 2>/dev/null || true
  fi
fi

# 委譲・レビューの子セッションには利用者がいないため、通知は司令塔のセッションにだけ出す。
[ -z "${AGENT_DELEGATED_SESSION:-}" ] || exit 0
[ -n "$latest" ] || exit 0
newest=$(printf '%s\n%s\n' "$imported" "$latest" | sort -V | tail -n 1)
if [ "$newest" != "$imported" ]; then
  cat <<MSG
<superpowers-import>
kata の工程 skill へ取り込んだ superpowers の上流に新しい版 $latest が出ている (取り込み済みは $imported)。最初の応答で利用者にこのことを伝える。取り込みを頼まれたら、$(dirname "$agent_shared")/docs/agents.md の「superpowers の取り込み」の手順で進める。
</superpowers-import>
MSG
fi
exit 0
