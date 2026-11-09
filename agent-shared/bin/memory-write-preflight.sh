#!/usr/bin/env bash
# Memory write preflight: bootstrap 手順 1-4 (正本解決 / link 照合 / lock 取得 /
# 前提検証 / pull --rebase / 再検証) を 1 回の Bash 呼び出しにまとめ、tool call
# 往復を減らす。
#
# usage: memory-write-preflight.sh <memory-link-path> [--read-sync]
# --read-sync は起動時の同期。fetch は lock の外で 8 秒で打ち切る。更新が無ければ lock を
#   取らずに終え、更新があれば lock を取って fast-forward し、解放してから返す。
#   <memory-link-path> は agent home 側の link (~/.claude/memory or ~/.codex/memory)。
# 正本の解決は resolve-memory-dir.sh に委ね、同じ env 契約 (AGENT_MEMORY_DIR など) に従う。
# exit contract: 通常の成功は exit 0 + stdout に opaque lock handle 1 行、lock は保持したまま。
#   --read-sync の成功は exit 0 + stdout 空、lock は保持していない。
#   失敗は非 0 + stdout 空。ここで取得した lock は解放して返す (解放失敗は stderr に
#   警告し、lock は手動 recovery に委ねる)。他プロセスの lock には触らない。
set -u

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

warn() { echo "memory-write-preflight: $1" >&2; }

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
      status=1
    fi
  fi
  exit "$status"
}

# bootstrap 手順 3 の前提: main / upstream origin/main / clean /
# merge・rebase 中でない / ahead 0。stage=post では pull 後なので behind 0 も要求。
# --read-sync は lock の外でも呼ぶので、writer の index.lock と衝突しないよう
# optional lock (index の refresh 書き込み) は取らない。
verify_repo_state() {
  local repo="$1" stage="$2" branch upstream status_output git_dir marker
  local counts behind ahead

  branch="$(git -C "$repo" symbolic-ref --short -q HEAD)" \
    && [ "$branch" = main ] || { warn "$stage: branch is not main"; return 1; }
  upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name \
    '@{upstream}' 2>/dev/null)" \
    && [ "$upstream" = origin/main ] \
    || { warn "$stage: upstream is not origin/main"; return 1; }
  status_output="$(git --no-optional-locks -C "$repo" status --porcelain)" \
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

# --read-sync の取得先。writer が使う origin/main・FETCH_HEAD とは別の ref に置き、
# lock の外で通信しても writer の pull・push と ref の更新が衝突しないようにする。
# --refmap= は、設定の fetch refspec による origin/main の便乗更新を止める。
READ_SYNC_REF=refs/memory-read-sync/main

link="${1:-}"
read_sync=false
if [ "$#" -eq 2 ] && [ "$2" = --read-sync ]; then
  read_sync=true
elif [ "$#" -ne 1 ]; then
  warn "usage: memory-write-preflight.sh <memory-link-path> [--read-sync]"
  exit 2
fi
if [ -z "$link" ]; then
  warn "memory link is required"
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

if [ "$read_sync" = true ]; then
  # 通信は lock の外で行い、lock は main を進める区間だけ保持する。
  verify_repo_state "$memory_repo" pre || exit 1
  # Python は検索にも必要。POSIX と Windows の双方で transport の子孫も終了する。
  # 通信が止まっても fetch を 8 秒で打ち切り、起動時 hook の timeout(20 秒)より前に注入へ進む。
  # GitHub への SSH fetch は接続と認証だけで 3 秒を超えることがあり、それより短い上限では
  # 正常な同期まで毎回打ち切られる。
  py_bin=$(command -v python3 || command -v python) || exit 1
  "$py_bin" - "$memory_repo" "+refs/heads/main:$READ_SYNC_REF" <<'PY' || exit 1
import os
import signal
import subprocess
import sys

process = subprocess.Popen(
    ["git", "-C", sys.argv[1], "fetch", "--quiet", "--no-write-fetch-head", "--refmap=",
     "origin", sys.argv[2]],
    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    env={**os.environ, "GIT_TERMINAL_PROMPT": "0", "GCM_INTERACTIVE": "never"},
    start_new_session=os.name != "nt")
try:
    status = process.wait(timeout=8)
except subprocess.TimeoutExpired:
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
    else:
        os.killpg(process.pid, signal.SIGKILL)
    process.wait(timeout=1)
    print("memory read sync: fetch timed out", file=sys.stderr)
    sys.exit(1)
if status:
    print("memory read sync: fetch failed", file=sys.stderr)
sys.exit(status)
PY
  revs="$(git -C "$memory_repo" rev-parse 'HEAD^{commit}' \
    'refs/remotes/origin/main^{commit}' "$READ_SYNC_REF^{commit}" 2>/dev/null)" \
    || { warn "read sync: fetched commit could not be resolved"; exit 1; }
  { read -r local_head; read -r tracking; read -r fetched; } <<<"$revs"
  [ -n "${fetched:-}" ] || { warn "read sync: fetched commit could not be resolved"; exit 1; }
  if [ "$local_head" = "$fetched" ] && [ "$tracking" = "$fetched" ]; then
    # 更新が無ければ lock を取らない。成功の条件は lock を取る経路の post 検証と揃える。
    # acquire が拒む状態(lock 保持中・回復待ち・不正な state root)は未同期として返す。
    bash "$BIN_DIR/memory-write-lock.sh" idle "$memory_repo"       || { warn "read sync: write lock is held or needs recovery"; exit 1; }
    verify_repo_state "$memory_repo" post || exit 1
    exit 0
  fi
fi

# 手順 2: 同一プロセスで再解決した正本を渡して lock を取得する。
# trap は acquire より前に張る。取得成功の瞬間から解放を保証するためで、
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
# 手順 3-4: lock を保持したまま前提を検証し、pull --rebase 後に再検証する。
# git の進捗出力は stdout 1 行 (handle) の契約を守るため stderr へ流す。
verify_repo_state "$memory_repo" pre || exit 1
if [ "$read_sync" = true ]; then
  # origin/main は従来の非強制 fetch と同じく fast-forward でだけ進める。lock を待つ間に
  # writer の push で origin/main が先へ進んでいれば、取得した commit では戻さない。
  # 記憶 repo は force push を禁止しているので、remote 側の巻き戻しはここでは扱わない。
  tracking="$(git -C "$memory_repo" rev-parse 'refs/remotes/origin/main^{commit}')" \
    || { warn "read sync: origin/main could not be resolved"; exit 1; }
  if [ "$tracking" != "$fetched" ] \
    && ! git -C "$memory_repo" merge-base --is-ancestor "$fetched" "$tracking"; then
    git -C "$memory_repo" merge-base --is-ancestor "$tracking" "$fetched" \
      || { warn "read sync: origin/main would not fast-forward"; exit 1; }
    git -C "$memory_repo" update-ref -m "memory read sync" \
      refs/remotes/origin/main "$fetched" "$tracking" \
      || { warn "read sync: origin/main could not be updated"; exit 1; }
  fi
  git -C "$memory_repo" merge --ff-only --no-edit origin/main >&2 || exit 1
  verify_repo_state "$memory_repo" post || exit 1
  # EXIT trap が所有する lock だけを解放する。handle は呼び出し側へ移譲しない。
  exit 0
fi
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
preflight_owns_lock=false
exit 0
