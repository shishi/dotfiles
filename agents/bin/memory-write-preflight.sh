#!/usr/bin/env bash
# Memory write preflight: bootstrap 手順 1-4 (正本解決 / link 照合 / lock 取得 /
# 前提検証 / pull --rebase / 再検証) を 1 回の Bash 呼び出しにまとめ、tool call
# 往復を減らす。
#
# usage: memory-write-preflight.sh <memory-link-path>
#   <memory-link-path> は agent home 側の link (~/.claude/memory or ~/.codex/memory)。
# 正本の解決は resolve-memory-dir.sh に委ね、同じ env 契約 (AGENT_MEMORY_DIR など) に従う。
# exit contract: 成功は exit 0 + stdout に opaque lock handle 1 行、lock は保持したまま。
#   失敗は非 0 + stdout 空。ここで取得した lock は解放して返す (解放失敗は stderr に
#   警告し、lock は手動 recovery に委ねる)。他プロセスの lock には触らない。
set -u

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

warn() { echo "memory-write-preflight: $1" >&2; }

# テスト専用の境界注入点。env 未設定の通常実行では no-op。
# signal 到達窓 (マイクロ秒級) を契約テストが決定的に狙えるようにする。
test_pause() { if [ -n "$1" ]; then sleep "$1"; fi; }

# lock 保持中の全終了経路 (失敗 exit・HUP/INT/TERM) で自分の lock だけを解放する。
# 成功時は handle の移譲完了後に preflight_owns_lock=false で解放を止める。
preflight_owns_lock=false
finish_preflight() {
  local status=$?
  trap '' HUP INT TERM PIPE
  trap - EXIT
  if [ "$preflight_owns_lock" = true ] && [ -n "${handle:-}" ]; then
    if ! bash "$BIN_DIR/memory-write-lock.sh" release "$handle"; then
      warn "write lock could not be released; manual recovery is required"
    fi
  fi
  exit "$status"
}

# bootstrap 手順 3 の前提: main / upstream origin/main / clean /
# merge・rebase 中でない / ahead 0。stage=post では pull 後なので behind 0 も要求。
verify_repo_state() {
  local repo="$1" stage="$2" branch upstream status_output git_dir marker
  local counts behind ahead

  branch="$(git -C "$repo" symbolic-ref --short -q HEAD)" \
    && [ "$branch" = main ] || { warn "$stage: branch is not main"; return 1; }
  upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name \
    '@{upstream}' 2>/dev/null)" \
    && [ "$upstream" = origin/main ] \
    || { warn "$stage: upstream is not origin/main"; return 1; }
  status_output="$(git -C "$repo" status --porcelain)" \
    || { warn "$stage: worktree state could not be determined"; return 1; }
  [ -z "$status_output" ] \
    || { warn "$stage: worktree is not clean"; return 1; }
  git_dir="$(git -C "$repo" rev-parse --absolute-git-dir 2>/dev/null)" \
    || { warn "$stage: git dir could not be resolved"; return 1; }
  for marker in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD; do
    if [ -e "$git_dir/$marker" ]; then
      warn "$stage: merge or rebase is in progress"
      return 1
    fi
  done
  counts="$(git -C "$repo" rev-list --left-right --count \
    '@{upstream}...HEAD' 2>/dev/null)" \
    || { warn "$stage: ahead/behind could not be determined"; return 1; }
  read -r behind ahead <<<"$counts"
  [ "$ahead" = 0 ] || { warn "$stage: local commits are ahead of origin/main"; return 1; }
  if [ "$stage" = post ] && [ "$behind" != 0 ]; then
    warn "post: still behind origin/main after pull"
    return 1
  fi
}

link="${1:-}"
if [ -z "$link" ] || [ "$#" -ne 1 ]; then
  warn "usage: memory-write-preflight.sh <memory-link-path>"
  exit 2
fi

# 手順 1: 正本を解決し、agent home の link が物理的に同じ場所を指すことを確認する。
memory_repo="$(bash "$BIN_DIR/resolve-memory-dir.sh")" \
  || { warn "memory repo could not be resolved"; exit 1; }
repo_physical="$(cd "$memory_repo" 2>/dev/null && pwd -P)" \
  || { warn "memory repo is not accessible"; exit 1; }
link_physical="$(cd "$link" 2>/dev/null && pwd -P)" \
  || { warn "memory link is not accessible"; exit 1; }
if [ "$link_physical" != "$repo_physical" ]; then
  warn "memory link does not resolve to the canonical repo"
  exit 1
fi
# lock helper は字句的に canonical なパスしか受けないため、照合済みの物理パスへ揃える。
memory_repo="$repo_physical"

# 手順 2: 同一プロセスで再解決した正本を渡して lock を取得する。
# trap は acquire より前に張る。取得成功の瞬間から解放保証を効かせるためで、
# 取得後に張ると trap 設置までの数命令が lock を漏らす窓になる。
# handle が空のまま死んだ場合は finish_preflight のガードが release を抑止する
# (acquire 自身の失敗掃除は lock helper 内部の trap が行う)。
trap finish_preflight EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 141' PIPE
trap 'exit 143' TERM
preflight_owns_lock=true
handle="$(bash "$BIN_DIR/memory-write-lock.sh" acquire "$memory_repo")" \
  || { warn "write lock could not be acquired"; exit 1; }
if [ -z "$handle" ]; then
  warn "write lock helper returned no handle"
  exit 1
fi
test_pause "${PREFLIGHT_PAUSE_AFTER_ACQUIRE:-}"

# 手順 3-4: lock を保持したまま前提を検証し、pull --rebase 後に再検証する。
# git の進捗出力は stdout 1 行 (handle) の契約を守るため stderr へ流す。
verify_repo_state "$memory_repo" pre || exit 1
git -C "$memory_repo" pull --rebase >&2 \
  || { warn "git pull --rebase failed"; exit 1; }
verify_repo_state "$memory_repo" post || exit 1

# 移譲区間に入る前に signal を無視する。handle 出力後に nonzero 終了すると、
# 「失敗は stdout 空」の契約が破れ、呼び出し側は有効な handle を捨ててしまう。
# PIPE を無視すると読み手消失は printf の write error になり、失敗経路へ落ちる。
trap '' HUP INT TERM PIPE
# handle が呼び出し側へ渡って初めて解放責任が移る。出力に失敗したら自分で解放する。
printf '%s\n' "$handle" \
  || { warn "lock handle could not be transferred"; exit 1; }
test_pause "${PREFLIGHT_PAUSE_AFTER_TRANSFER:-}"
preflight_owns_lock=false
test_pause "${PREFLIGHT_PAUSE_BEFORE_EXIT:-}"
exit 0
