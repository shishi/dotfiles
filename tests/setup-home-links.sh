#!/usr/bin/env bash
# setup.sh が agent ホーム (~/.codex、~/.claude) と personal skills
# (~/.agents/skills) の symlink を張ることの検証。
# - 削除済みヘルパー codex-tools/setup-home-links.sh (このファイルとは別物) の
#   責務を setup.sh へ取り込んだため、
#   外部ヘルパー (と Python) への依存が残っていないことも見る
# - 既存の実ディレクトリ (auth.json / sessions が入っている) は壊さないこと
# - ~/.codex と ~/.claude は同じ構造 (ignore 配下に runtime を持つホームごとの
#   リンク) なので、同じ判定を通ること
set -u

# fixture 側で「既存リンク」を作るのはこのテスト自身なので、setup.sh と同じ export が
# 必要。無いと Git Bash の ln -s は symlink ではなくコピーを作り、検証したい状態
# (別 checkout を指すリンク) が実ディレクトリになって別の分岐を測ってしまう。
case "$(uname -s)" in
  MINGW* | MSYS*) export MSYS=winsymlinks:nativestrict ;;
esac

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="${REPO}/setup.sh"
SYSTEM_GIT="$(command -v git)"
SYSTEM_MV="$(command -v mv)"
case "$(uname -s)" in
  Darwin | *BSD) SYSTEM_MV_NOFOLLOW_OPTION=-h ;;
  *) SYSTEM_MV_NOFOLLOW_OPTION=-T ;;
esac
SYSTEM_MKDIR="$(command -v mkdir)"
SYSTEM_RM="$(command -v rm)"
SYSTEM_LN="$(command -v ln)"
PASS=0
FAIL=0
ok() {
  PASS=$((PASS + 1))
  echo "ok: $1"
}
ng() {
  FAIL=$((FAIL + 1))
  echo "NG: $1"
}

component_log_block() {
  local file="$1" component="$2" header

  header="setup.sh: ${component}"

  [ "$(grep -cxF "$header" "$file")" = 1 ] || return 1
  awk -v header="$header" '
    $0 == header { in_block = 1 }
    in_block && $0 != header && /^setup[.]sh: / { exit }
    in_block && $0 == "please reload shell" { exit }
    in_block { print }
  ' "$file"
}

write_herdr_hook_configs() {
  local root="$1"

  cat >"${root}/dotfiles/claude/settings.json" <<'EOF'
{"hooks":{"SessionStart":[{"matcher":"*","hooks":[{"type":"command","command":"bash ~/.claude/hooks/herdr-agent-state.sh session","timeout":10}]}]}}
EOF
  cat >"${root}/dotfiles/codex/hooks.json" <<'EOF'
{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash ~/.codex/herdr-agent-state.sh session","commandWindows":"& 'C:/Users/shishi/scoop/apps/git/current/bin/bash.exe' -c '~/.codex/herdr-agent-state.sh session'","timeout":10}]}]}}
EOF
}

# 実マシンの herdr-bootstrap が PATH 経由で漏れ込むと、herdr CLI 直呼びの
# fallback 経路を検証するケースが bootstrap 側へ逸れる。fixture ごとに隠す。
write_hide_herdr_bootstrap() {
  local root="$1"

  cat >"${root}/hide-herdr-bootstrap.sh" <<'EOF'
command() {
  if [ "${1:-}" = -v ] && [ "${2:-}" = herdr-bootstrap ]; then
    return 1
  fi
  builtin command "$@"
}
EOF
}

# herdr の fake を置かないケースで、実マシンの herdr / herdr-bootstrap が
# 呼ばれないよう両方を隠す(herdr の呼び出しは daemon 接続を伴うため)。
write_hide_herdr_all() {
  local root="$1"

  cat >"${root}/hide-herdr-all.sh" <<'EOF'
command() {
  if [ "${1:-}" = -v ]; then
    case "${2:-}" in
      herdr | herdr-bootstrap) return 1 ;;
    esac
  fi
  builtin command "$@"
}
EOF
}

make_temp_root() {
  local variable="$1" path physical_path
  if ! path="$(mktemp -d)"; then
    echo "fatal: mktemp failed for $variable" >&2
    exit 1
  fi
  if ! physical_path="$(cd "$path" && pwd -P)"; then
    echo "fatal: could not resolve temporary root for $variable: $path" >&2
    exit 1
  fi
  printf -v "$variable" '%s' "$physical_path"
}

# setup.sh は自分の位置から DOTDIR を導くので、fixture へコピーすれば実 HOME に
# 触らずに検証できる。REMOTE_CONTAINERS=true は emacs の clone 分岐を飛ばす。
make_fixture() {
  local root="$1"
  mkdir -p "${root}/dotfiles/codex/skills" "${root}/dotfiles/nushell" \
    "${root}/dotfiles/claude" "${root}/dotfiles/agents/bin" \
    "${root}/dotfiles/agents/hooks" "${root}/home" "${root}/config" \
    "${root}/agent-memory" "${root}/bin"
  cp "$SETUP" "${root}/dotfiles/setup.sh"
  cp "${REPO}/agents/bin/resolve-memory-dir.sh" "${root}/dotfiles/agents/bin/resolve-memory-dir.sh"
  cp "${REPO}/agents/hooks/inject-memory.sh" "${root}/dotfiles/agents/hooks/inject-memory.sh"
  : >"${root}/dotfiles/nushell/config.nu"
  : >"${root}/dotfiles/nushell/env.nu"
  : >"${root}/dotfiles/claude/install-plugins.sh"
  : >"${root}/dotfiles/.gitconfig.win"
  : >"${root}/dotfiles/.gitconfig.linux"
  : >"${root}/dotfiles/.gitconfig.mac"
  : >"${root}/agent-memory/MEMORY.md"
  : >"${root}/agent-memory/CONVENTIONS.md"
  "$SYSTEM_GIT" -C "${root}/agent-memory" init -q
  "$SYSTEM_GIT" -C "${root}/agent-memory" branch -M main
  "$SYSTEM_GIT" -C "${root}/agent-memory" config user.name setup-test
  "$SYSTEM_GIT" -C "${root}/agent-memory" config user.email setup-test@example.invalid
  "$SYSTEM_GIT" -C "${root}/agent-memory" config commit.gpgSign false
  "$SYSTEM_GIT" -C "${root}/agent-memory" remote add origin \
    git@github.com:shishi/agent-memory.git
  "$SYSTEM_GIT" -C "${root}/agent-memory" add MEMORY.md CONVENTIONS.md
  "$SYSTEM_GIT" -C "${root}/agent-memory" commit -qm 'initial memory'
  cat >"${root}/bin/git" <<'EOF'
#!/bin/sh
if [ "${1:-}" = clone ]; then
  printf '%s %s\n' "$(basename "$0")" "$*" >>"$SETUP_EXTERNAL_CALL_LOG"
  exit 97
fi
exec "$SETUP_SYSTEM_GIT" "$@"
EOF
  cp "${root}/bin/git" "${root}/bin/gh"
  chmod +x "${root}/bin/git" "${root}/bin/gh"
}

run_setup() {
  local root="$1"
  HOME="${root}/home" XDG_CONFIG_HOME="${root}/config" REMOTE_CONTAINERS=true \
    BASH_ENV="${SETUP_BASH_ENV:-}" \
    AGENT_MEMORY_DIR="${root}/agent-memory" \
    SETUP_SYSTEM_GIT="$SYSTEM_GIT" \
    SETUP_SYSTEM_MV="$SYSTEM_MV" \
    SYSTEM_MV_NOFOLLOW_OPTION="$SYSTEM_MV_NOFOLLOW_OPTION" \
    SETUP_SYSTEM_MKDIR="$SYSTEM_MKDIR" \
    SETUP_SYSTEM_RM="$SYSTEM_RM" SETUP_SYSTEM_LN="$SYSTEM_LN" \
    SETUP_EXTERNAL_CALL_LOG="${root}/external-calls.log" PATH="${root}/bin:$PATH" \
    FAIL_MEMORY_LINK_PREFIX="${FAIL_MEMORY_LINK_PREFIX:-}" \
    SETUP_LN_LOG="${root}/ln.log" \
    FAIL_MEMORY_MOVE_TARGET="${FAIL_MEMORY_MOVE_TARGET:-}" \
    SETUP_MV_LOG="${root}/mv.log" SETUP_MV_STATE="${root}/mv.state" \
    MUTATE_MEMORY_TARGET="${MUTATE_MEMORY_TARGET:-}" \
    MUTATE_MEMORY_LITERAL="${MUTATE_MEMORY_LITERAL:-}" \
    MUTATE_MEMORY_BACKUP_PREFIX="${MUTATE_MEMORY_BACKUP_PREFIX:-}" \
    MUTATE_MEMORY_BACKUP_LITERAL="${MUTATE_MEMORY_BACKUP_LITERAL:-}" \
    INTERLEAVE_MOVE_TARGET="${INTERLEAVE_MOVE_TARGET:-}" \
    INTERLEAVE_MOVE_LITERAL="${INTERLEAVE_MOVE_LITERAL:-}" \
    INTERLEAVE_MOVE_KIND="${INTERLEAVE_MOVE_KIND:-symlink}" \
    SETUP_MOVE_OPTION_LOG="${root}/move-options.log" \
    FAIL_BACKUP_RM_PREFIX="${FAIL_BACKUP_RM_PREFIX:-}" \
    SETUP_RM_LOG="${root}/rm.log" \
    SIGNAL_AFTER_MOVE_TARGET="${SIGNAL_AFTER_MOVE_TARGET:-}" \
    MOVE_REPO_SOURCE="${MOVE_REPO_SOURCE:-}" MOVE_REPO_DEST="${MOVE_REPO_DEST:-}" \
    MOVE_REPO_STATE="${root}/move-repo.state" \
    bash "${root}/dotfiles/setup.sh" >>"${root}/setup.log" 2>&1
}

# Windows では readlink の表記が揺れるため、解決後の実パスで比較する。
resolves_to() {
  local link="$1" expected="$2" actual
  [ -L "$link" ] || return 1
  actual="$(cd "$link" 2>/dev/null && pwd -P)" || return 1
  expected="$(cd "$expected" 2>/dev/null && pwd -P)" || return 1
  [ "$actual" = "$expected" ]
}

# ファイルへのリンク用。resolves_to は cd するのでディレクトリしか見られない。
# 解決できない側は空文字になるため、空同士が一致して通らないよう非空も見る。
resolves_to_file() {
  local link="$1" expected="$2" actual target
  [ -L "$link" ] || return 1
  actual="$(realpath "$link" 2>/dev/null)" || return 1
  target="$(realpath "$expected" 2>/dev/null)" || return 1
  [ -n "$actual" ] && [ -n "$target" ] && [ "$actual" = "$target" ]
}

# memory transaction の temp/backup は target と同じ directory の immediate child。
# glob が無マッチなら literal 自体を 1 回検査して偽になるため nullglob は不要。
memory_setup_artifacts_absent() {
  local directory artifact

  for directory in "$@"; do
    for artifact in "$directory"/memory.setup-*; do
      if [ -e "$artifact" ] || [ -L "$artifact" ]; then
        return 1
      fi
    done
  done
  return 0
}

directory_is_empty() {
  local directory="$1" entry
  for entry in "$directory"/* "$directory"/.[!.]* "$directory"/..?*; do
    if [ -e "$entry" ] || [ -L "$entry" ]; then
      return 1
    fi
  done
  return 0
}

count_barrier_tokens() {
  local directory="$1" token count=0
  for token in "$directory"/arrived.*; do
    [ -e "$token" ] || continue
    count=$((count + 1))
  done
  printf '%s\n' "$count"
}

install_concurrency_barriers() {
  local root="$1"

  mkdir -p "${root}/barrier-lock" "${root}/barrier-mv"
  cat >"${root}/bin/mkdir" <<'EOF'
#!/bin/sh
last=""
for arg in "$@"; do last="$arg"; done
if [ "$last" = "$SETUP_MEMORY_LOCK" ]; then
  : >"$SETUP_LOCK_BARRIER/arrived.$$"
  attempts=0
  while [ "$(count=0; for token in "$SETUP_LOCK_BARRIER"/arrived.*; do [ -e "$token" ] && count=$((count + 1)); done; echo "$count")" -lt 2 ]; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 10 ] || exit 75
    sleep 1
  done
  if "$SETUP_SYSTEM_MKDIR" "$@"; then
    : >"$SETUP_LOCK_BARRIER/winner"
    attempts=0
    while [ ! -e "$SETUP_LOCK_BARRIER/loser" ]; do
      attempts=$((attempts + 1))
      [ "$attempts" -lt 10 ] || exit 77
      sleep 1
    done
    exit 0
  else
    status=$?
    : >"$SETUP_LOCK_BARRIER/loser"
    exit "$status"
  fi
fi
exec "$SETUP_SYSTEM_MKDIR" "$@"
EOF
  cat >"${root}/bin/mv" <<'EOF'
#!/bin/sh
last=""
for arg in "$@"; do last="$arg"; done
if [ "$last" = "$SETUP_CONCURRENT_MOVE_TARGET" ] && [ ! -d "$SETUP_MEMORY_LOCK" ]; then
  : >"$SETUP_MV_BARRIER/arrived.$$"
  attempts=0
  while [ "$(count=0; for token in "$SETUP_MV_BARRIER"/arrived.*; do [ -e "$token" ] && count=$((count + 1)); done; echo "$count")" -lt 2 ]; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 10 ] || exit 76
    sleep 1
  done
fi
exec "$SETUP_SYSTEM_MV" "$@"
EOF
  chmod +x "${root}/bin/mkdir" "${root}/bin/mv"
}

install_recording_mv() {
  local root="$1"

  cat >"${root}/bin/mv" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$SETUP_MOVE_OPTION_LOG"
case "${1:-}" in
  -h | -T)
    shift
    exec "$SETUP_SYSTEM_MV" "$SYSTEM_MV_NOFOLLOW_OPTION" "$@"
    ;;
  *) exec "$SETUP_SYSTEM_MV" "$@" ;;
esac
EOF
  chmod +x "${root}/bin/mv"
}

install_fake_uname() {
  local root="$1" platform="$2"

  cat >"${root}/bin/uname" <<EOF
#!/bin/sh
printf '%s\\n' '$platform'
EOF
  chmod +x "${root}/bin/uname"
}

install_interleaving_mv() {
  local root="$1"

  cat >"${root}/bin/mv" <<'EOF'
#!/bin/sh
last=""
for arg in "$@"; do last="$arg"; done
if [ "$last" = "$INTERLEAVE_MOVE_TARGET" ] && [ ! -e "$SETUP_MV_STATE" ]; then
  : >"$SETUP_MV_STATE"
  if [ "$INTERLEAVE_MOVE_KIND" = file ]; then
    printf 'keep\n' >"$INTERLEAVE_MOVE_TARGET"
  else
    "$SETUP_SYSTEM_LN" -s "$INTERLEAVE_MOVE_LITERAL" "$INTERLEAVE_MOVE_TARGET"
  fi
fi
exec "$SETUP_SYSTEM_MV" "$@"
EOF
  chmod +x "${root}/bin/mv"
}

install_failing_mv() {
  local root="$1"

  cat >"${root}/bin/mv" <<'EOF'
#!/bin/sh
last=""
for arg in "$@"; do last="$arg"; done
if [ "$last" = "$FAIL_MEMORY_MOVE_TARGET" ] && [ ! -e "$SETUP_MV_STATE" ]; then
  : >"$SETUP_MV_STATE"
  printf 'injected mv failure: %s\n' "$last" >>"$SETUP_MV_LOG"
  if [ -n "$MUTATE_MEMORY_TARGET" ]; then
    "$SETUP_SYSTEM_RM" -f "$MUTATE_MEMORY_TARGET"
    "$SETUP_SYSTEM_LN" -s "$MUTATE_MEMORY_LITERAL" "$MUTATE_MEMORY_TARGET"
  fi
  if [ -n "$MUTATE_MEMORY_BACKUP_PREFIX" ]; then
    for backup in "$MUTATE_MEMORY_BACKUP_PREFIX"*.back; do
      [ -L "$backup" ] || continue
      "$SETUP_SYSTEM_RM" -f "$backup"
      "$SETUP_SYSTEM_LN" -s "$MUTATE_MEMORY_BACKUP_LITERAL" "$backup"
    done
  fi
  exit 74
fi
exec "$SETUP_SYSTEM_MV" "$@"
EOF
  chmod +x "${root}/bin/mv"
}

install_failing_backup_rm() {
  local root="$1"

  cat >"${root}/bin/rm" <<'EOF'
#!/bin/sh
last=""
for arg in "$@"; do last="$arg"; done
case "$last" in
  "$FAIL_BACKUP_RM_PREFIX"*.back)
    printf 'injected backup rm failure: %s\n' "$last" >>"$SETUP_RM_LOG"
    exit 78
    ;;
esac
exec "$SETUP_SYSTEM_RM" "$@"
EOF
  chmod +x "${root}/bin/rm"
}

install_signaling_mv() {
  local root="$1"

  cat >"${root}/bin/mv" <<'EOF'
#!/bin/sh
last=""
for arg in "$@"; do last="$arg"; done
"$SETUP_SYSTEM_MV" "$@"
status=$?
if [ "$status" -eq 0 ] && [ "$last" = "$SIGNAL_AFTER_MOVE_TARGET" ] \
  && [ ! -e "$SETUP_MV_STATE" ]; then
  : >"$SETUP_MV_STATE"
  kill -TERM "$PPID"
fi
exit "$status"
EOF
  chmod +x "${root}/bin/mv"
}

install_repo_moving_git() {
  local root="$1"

  cat >"${root}/bin/git" <<'EOF'
#!/bin/sh
case "$*" in
  *'cat-file -t '*'CONVENTIONS.md'*)
    "$SETUP_SYSTEM_GIT" "$@"
    status=$?
    if [ "$status" -eq 0 ] && [ ! -e "$MOVE_REPO_STATE" ]; then
      : >"$MOVE_REPO_STATE"
      "$SETUP_SYSTEM_MV" "$MOVE_REPO_SOURCE" "$MOVE_REPO_DEST"
    fi
    exit "$status"
    ;;
esac
exec "$SETUP_SYSTEM_GIT" "$@"
EOF
  chmod +x "${root}/bin/git"
}

install_recording_memory_ln() {
  local root="$1"

  cat >"${root}/bin/ln" <<'EOF'
#!/bin/sh
last=""
for arg in "$@"; do last="$arg"; done
case "$last" in
  */memory.setup-*.new) printf '%s\n' "$last" >>"$SETUP_LN_LOG" ;;
esac
exec "$SETUP_SYSTEM_LN" "$@"
EOF
  chmod +x "${root}/bin/ln"
}

install_signal_blocking_git() {
  local root="$1"

  cat >"${root}/bin/git" <<'EOF'
#!/bin/sh
case "$*" in
  *'rev-parse --show-toplevel'*)
    if [ -n "${SIGNAL_FOREIGN_OWNER:-}" ]; then
      printf '%s\n' "$SIGNAL_FOREIGN_OWNER" >"$HOME/.agent-memory-setup.lock/owner"
    fi
    : >"$SIGNAL_READY"
    sleep 3
    ;;
esac
exec "$SETUP_SYSTEM_GIT" "$@"
EOF
  chmod +x "${root}/bin/git"
}

start_setup_for_signal() {
  local root="$1"
  HOME="${root}/home" XDG_CONFIG_HOME="${root}/config" REMOTE_CONTAINERS=true \
    AGENT_MEMORY_DIR="${root}/agent-memory" SETUP_SYSTEM_GIT="$SYSTEM_GIT" \
    SETUP_SYSTEM_MV="$SYSTEM_MV" SETUP_SYSTEM_MKDIR="$SYSTEM_MKDIR" \
    SETUP_SYSTEM_RM="$SYSTEM_RM" SETUP_SYSTEM_LN="$SYSTEM_LN" \
    SETUP_EXTERNAL_CALL_LOG="${root}/external-calls.log" PATH="${root}/bin:$PATH" \
    SIGNAL_READY="${root}/signal.ready" \
    SIGNAL_FOREIGN_OWNER="${SIGNAL_FOREIGN_OWNER:-}" \
    bash "${root}/dotfiles/setup.sh" >>"${root}/setup.log" 2>&1 &
  SIGNAL_SETUP_PID=$!
}

start_setup_for_int() {
  local root="$1"
  set -m
  HOME="${root}/home" XDG_CONFIG_HOME="${root}/config" REMOTE_CONTAINERS=true \
    AGENT_MEMORY_DIR="${root}/agent-memory" SETUP_SYSTEM_GIT="$SYSTEM_GIT" \
    SETUP_SYSTEM_MV="$SYSTEM_MV" SETUP_SYSTEM_MKDIR="$SYSTEM_MKDIR" \
    SETUP_SYSTEM_RM="$SYSTEM_RM" SETUP_SYSTEM_LN="$SYSTEM_LN" \
    SETUP_EXTERNAL_CALL_LOG="${root}/external-calls.log" PATH="${root}/bin:$PATH" \
    SIGNAL_READY="${root}/signal.ready" SIGNAL_FOREIGN_OWNER="" \
    bash "${root}/dotfiles/setup.sh" >>"${root}/setup.log" 2>&1 &
  SIGNAL_SETUP_PID=$!
  set +m
}

wait_for_file() {
  local path="$1" attempts=0
  while [ ! -e "$path" ]; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 10 ] || return 1
    sleep 1
  done
}

# (1) fresh 環境で 2 本のリンクが張られる
make_temp_root T1
trap 'rm -rf "$T1" "${T2:-}" "${T3:-}" "${T4:-}" "${T5:-}" "${T6:-}" "${T7:-}" "${T8:-}" "${T9:-}" "${T10:-}" "${T11:-}" "${T12:-}" "${T13:-}" "${T14:-}" "${T15:-}" "${T16:-}" "${T17:-}" "${T18:-}" "${T19:-}" "${T20:-}" "${T21:-}" "${T22:-}" "${T23:-}" "${T24:-}" "${T25:-}" "${T26:-}" "${T27:-}" "${T28:-}" "${T29:-}" "${T30:-}" "${T31:-}" "${T32:-}" "${T33:-}" "${T34:-}" "${T35:-}" "${T36:-}" "${T37:-}" "${T38:-}" "${T39:-}" "${T40:-}" "${T41:-}" "${T42:-}" "${T43:-}" "${T44:-}" "${T45:-}" "${T46:-}" "${T47:-}" "${T48:-}" "${T49:-}"' EXIT
make_fixture "$T1"
run_setup "$T1"
# setup.sh には set -e が無く末尾の echo で必ず exit 0 になるため、終了コードでは
# なくログを見る。"could not ..." 側は Codex ブロックの文言に絞ってあるが、
# ^(ln|mkdir): は fish / nvim / helix / nushell など他ブロックの stderr も拾う。
# 前提は make_fixture が「リンク先の親」を作っていること (${root}/config と
# ${root}/home)。リンク元は無くてよい (ln -s は存在しない source でも成功して
# dangling link を作る)。親を削り込むとここが無関係な失敗で落ちる。
LINK_FAILURE='^(ln|mkdir): |could not link|could not create ~/\.agents|missing link source'
if grep -qE "$LINK_FAILURE" "${T1}/setup.log"; then
  ng "setup.sh reported a link failure on a fresh fixture home (see below)"
  grep -nE "$LINK_FAILURE" "${T1}/setup.log" >&2
else
  ok "setup.sh links without reporting a failure on a fresh fixture home"
fi
if resolves_to "${T1}/home/.codex" "${T1}/dotfiles/codex"; then
  ok "~/.codex links to dotfiles/codex"
else
  ng "~/.codex does not link to dotfiles/codex"
fi
if resolves_to "${T1}/home/.agents/skills" "${T1}/dotfiles/codex/skills"; then
  ok "~/.agents/skills links to dotfiles/codex/skills"
else
  ng "~/.agents/skills does not link to dotfiles/codex/skills"
fi
if resolves_to "${T1}/home/.agents/bin" "${T1}/dotfiles/agents/bin" \
  && resolves_to "${T1}/home/.agents/hooks" "${T1}/dotfiles/agents/hooks"; then
  ok "~/.agents shared runtime links to dotfiles/agents"
else
  ng "~/.agents shared runtime does not link to dotfiles/agents"
fi
if resolves_to "${T1}/dotfiles/claude/memory" "${T1}/agent-memory" \
  && resolves_to "${T1}/dotfiles/codex/memory" "${T1}/agent-memory"; then
  ok "Claude and Codex memory are symlinks to one canonical repository"
else
  ng "Claude and Codex memory do not both link to the canonical repository"
fi
if [ ! -s "${T1}/external-calls.log" ]; then
  ok "an existing canonical repository is reused without a second clone"
else
  ng "setup.sh attempted an external clone despite the canonical repository: $(cat "${T1}/external-calls.log")"
fi

# (2) 再実行しても壊れない (setup.sh は何度でも流せる前提)
run_setup "$T1"
if resolves_to "${T1}/home/.codex" "${T1}/dotfiles/codex" \
  && resolves_to "${T1}/home/.agents/skills" "${T1}/dotfiles/codex/skills" \
  && resolves_to "${T1}/home/.agents/bin" "${T1}/dotfiles/agents/bin" \
  && resolves_to "${T1}/home/.agents/hooks" "${T1}/dotfiles/agents/hooks" \
  && resolves_to "${T1}/dotfiles/claude/memory" "${T1}/agent-memory" \
  && resolves_to "${T1}/dotfiles/codex/memory" "${T1}/agent-memory"; then
  ok "re-running setup.sh keeps home and memory links intact"
else
  ng "re-running setup.sh broke a home or memory link"
fi

# (3) 実ディレクトリは .back へ退避して張り直す。実行後は必ずこの checkout を指す。
make_temp_root T2
make_fixture "$T2"
mkdir -p "${T2}/home/.codex"
echo "live-secret" >"${T2}/home/.codex/auth.json"
run_setup "$T2"
if resolves_to "${T2}/home/.codex" "${T2}/dotfiles/codex" \
  && [ "$(cat "${T2}/home/.codex.back/auth.json" 2>/dev/null)" = "live-secret" ]; then
  ok "a real ~/.codex moves to .back and the link is created"
else
  ng "a real ~/.codex was not backed up, or the link was not created"
fi
# 退避先を名指しする。runtime をどこから戻すのか判らないと Codex はサインアウトの
# まま残る。
if grep -q '\.codex to .*\.codex\.back' "${T2}/setup.log"; then
  ok "setup.sh names where it moved the real path"
else
  ng "setup.sh moved the real path without naming the backup"
fi
# 2 度目は .back が空いていないので、退避先を衝突させないこと。
mkdir -p "${T2}/home/.codex.stale" && rm -rf "${T2}/home/.codex" \
  && mv "${T2}/home/.codex.stale" "${T2}/home/.codex"
echo second >"${T2}/home/.codex/auth.json"
run_setup "$T2"
if resolves_to "${T2}/home/.codex" "${T2}/dotfiles/codex" \
  && [ "$(cat "${T2}/home/.codex.back/auth.json" 2>/dev/null)" = "live-secret" ] \
  && [ "$(cat "${T2}/home/.codex.back.1/auth.json" 2>/dev/null)" = "second" ]; then
  ok "a second backup does not overwrite the first"
else
  ng "the second backup collided with the first"
fi

# (4) 別 checkout を指すリンクも .back へ退避して張り直す。指し先の実体は動かさない。
make_temp_root T3
make_fixture "$T3"
mkdir -p "${T3}/other-checkout/codex/skills"
echo "live-secret" >"${T3}/other-checkout/codex/auth.json"
ln -sfn "${T3}/other-checkout/codex" "${T3}/home/.codex"
run_setup "$T3"
if resolves_to "${T3}/home/.codex" "${T3}/dotfiles/codex" \
  && [ "$(readlink "${T3}/home/.codex.back")" = "${T3}/other-checkout/codex" ]; then
  ok "a foreign link moves to .back and the link is repointed here"
else
  ng "a foreign link was not backed up, or was not repointed"
fi
# mv はリンク自身を動かすので、指し先の runtime は無傷でなければならない。
if [ "$(cat "${T3}/other-checkout/codex/auth.json" 2>/dev/null)" = "live-secret" ]; then
  ok "the other checkout's runtime is untouched"
else
  ng "the other checkout's runtime was moved or destroyed"
fi
# skills 側も同じ扱い。
ln -sfn "${T3}/other-checkout/codex/skills" "${T3}/home/.agents/skills"
run_setup "$T3"
if resolves_to "${T3}/home/.agents/skills" "${T3}/dotfiles/codex/skills" \
  && [ -L "${T3}/home/.agents/skills.back" ]; then
  ok "a foreign skills link moves to .back and is repointed here"
else
  ng "the foreign skills link was not backed up, or was not repointed"
fi
# 一方で dangling link は張り直す (checkout を移動した後の復旧経路)。捨てたリンク先を
# 報告することが、その値が残る唯一の経路なので併せて固定する。
ln -sfn "${T3}/gone/codex" "${T3}/home/.codex"
run_setup "$T3"
if resolves_to "${T3}/home/.codex" "${T3}/dotfiles/codex"; then
  ok "a dangling link is repaired"
else
  ng "setup.sh left a dangling Codex link in place"
fi
if grep -q 'was a dangling link to .*gone/codex' "${T3}/setup.log"; then
  ok "setup.sh records the dangling target it discarded"
else
  ng "setup.sh discarded a dangling link target without recording it"
fi

# (5) リンク元が無い checkout では dangling link を作らず報告する
make_temp_root T4
make_fixture "$T4"
rm -rf "${T4}/dotfiles/codex"
run_setup "$T4"
if [ ! -e "${T4}/home/.codex" ] && [ ! -L "${T4}/home/.codex" ]; then
  ok "a missing link source leaves no dangling link behind"
else
  ng "setup.sh created a link even though dotfiles/codex is missing"
fi
if grep -q 'missing .*/dotfiles/codex; skip' "${T4}/setup.log"; then
  ok "setup.sh names the missing link source"
else
  ng "setup.sh skipped the missing link source silently"
fi

# (6) 削除済みの外部ヘルパーを参照していない
if grep -q 'codex-tools' "$SETUP"; then
  ng "setup.sh still references the removed codex-tools helpers"
else
  ok "setup.sh has no codex-tools dependency"
fi

# (7) ~/.claude は ~/.codex と同じ構造なので、同じ判定を通る。ignore 配下に
# projects/ sessions/ history.jsonl plugins/ と agent-memory への memory リンクを
# 抱えたホームそのものなので、張り替えると Claude Code の実行状態が参照から外れる。
if resolves_to "${T1}/home/.claude" "${T1}/dotfiles/claude"; then
  ok "~/.claude links to dotfiles/claude"
else
  ng "~/.claude does not link to dotfiles/claude"
fi
# 正しいリンクを毎回 rm して張り直すと、~/.claude が存在しない窓が開く。resolve 先は
# 張り替えても同じなので、リンクの literal が保存されているかで見る (Windows でも
# 相対リンクの literal は verbatim に残る)。
( cd "${T1}/home" && rm -f .claude && ln -s ../dotfiles/claude .claude )
run_setup "$T1"
if [ "$(readlink "${T1}/home/.claude")" = "../dotfiles/claude" ]; then
  ok "an already-correct ~/.claude link is not removed and recreated"
else
  ng "setup.sh recreated a correct ~/.claude link (now '$(readlink "${T1}/home/.claude")')"
fi

make_temp_root T5
make_fixture "$T5"
mkdir -p "${T5}/home/.claude/projects"
echo "live-history" >"${T5}/home/.claude/history.jsonl"
run_setup "$T5"
if resolves_to "${T5}/home/.claude" "${T5}/dotfiles/claude" \
  && [ "$(cat "${T5}/home/.claude.back/history.jsonl" 2>/dev/null)" = "live-history" ]; then
  ok "a real ~/.claude moves to .back and the link is created"
else
  ng "a real ~/.claude was not backed up, or the link was not created"
fi
# 退避先を名指しする。session 履歴と資格情報をどこから戻すのか判らないと動けない。
if grep -q '\.claude to .*\.claude\.back' "${T5}/setup.log"; then
  ok "setup.sh names where it moved the real Claude path"
else
  ng "setup.sh moved the real Claude path without naming the backup"
fi

# 別 checkout を指すリンクも退避して張り直す。指し先の実体は動かさない。
rm -rf "${T5}/home/.claude" "${T5}/home/.claude.back"
mkdir -p "${T5}/other-checkout/claude/projects"
echo "live-history" >"${T5}/other-checkout/claude/history.jsonl"
ln -sfn "${T5}/other-checkout/claude" "${T5}/home/.claude"
run_setup "$T5"
if resolves_to "${T5}/home/.claude" "${T5}/dotfiles/claude" \
  && [ "$(readlink "${T5}/home/.claude.back")" = "${T5}/other-checkout/claude" ]; then
  ok "a foreign ~/.claude link moves to .back and is repointed here"
else
  ng "a foreign ~/.claude link was not backed up, or was not repointed"
fi
# mv はリンク自身を動かす。指し先の実体に触れていないこと (rm -fr 混入の番人)。
if [ -f "${T5}/other-checkout/claude/history.jsonl" ]; then
  ok "the other checkout's Claude runtime survives (rm -fr regression guard)"
else
  ng "the other checkout's Claude runtime was destroyed"
fi

# dangling link は張り直す。捨てたリンク先を報告することが、その値が残る唯一の経路。
ln -sfn "${T5}/gone/claude" "${T5}/home/.claude"
run_setup "$T5"
if resolves_to "${T5}/home/.claude" "${T5}/dotfiles/claude"; then
  ok "a dangling ~/.claude link is repaired"
else
  ng "setup.sh left a dangling ~/.claude link in place"
fi
if grep -q 'was a dangling link to .*gone/claude' "${T5}/setup.log"; then
  ok "setup.sh records the dangling Claude target it discarded"
else
  ng "setup.sh discarded a dangling ~/.claude target without recording it"
fi

# (8) bind mount (devcontainer) 検出は残っている。実 mount は fixture で作れないため
# 静的に見る。存在だけでなく順序も見る: link_agent_home へ渡した後ろへ動かすと、
# bind mount は「実パス」として扱われ、退避を促す remedy が mount 元へ向く。
# コメント行は数えない。同じ語はすぐ上の説明コメントにも出るので、素朴な head -1 だと
# 実コードを消してコメントだけ残した状態を緑にしてしまう。
code_line() {
  grep -nE "$1" "$SETUP" | grep -vE '^[0-9]+:[[:space:]]*#' | head -1 | cut -d: -f1
}
MOUNT_LINE="$(code_line 'mountpoint -q ~/\.claude')"
PROC_LINE="$(code_line 'grep -qE .*/proc/mounts')"
CLAUDE_CALL_LINE="$(code_line 'link_agent_home "\$\{DOTDIR\}/claude"')"
if [ -n "$MOUNT_LINE" ] && [ -n "$PROC_LINE" ] && [ -n "$CLAUDE_CALL_LINE" ] \
  && [ "$MOUNT_LINE" -lt "$CLAUDE_CALL_LINE" ] && [ "$PROC_LINE" -lt "$CLAUDE_CALL_LINE" ]; then
  ok "the bind mount check for ~/.claude runs before the shared link function"
else
  ng "the bind mount check for ~/.claude was dropped or moved after link_agent_home"
fi

# (9) ~/.agents/skills が実ディレクトリのときも 3 target で同じ扱い。
make_temp_root T6
make_fixture "$T6"
mkdir -p "${T6}/home/.agents/skills/.system"
printf 'runtime
' >"${T6}/home/.agents/skills/.system/state"
run_setup "$T6"
if resolves_to "${T6}/home/.agents/skills" "${T6}/dotfiles/codex/skills" \
  && [ -f "${T6}/home/.agents/skills.back/.system/state" ]; then
  ok "a real ~/.agents/skills moves to .back and the link is created"
else
  ng "a real ~/.agents/skills was not backed up, or the link was not created"
fi
if grep -q 'skills to .*skills\.back' "${T6}/setup.log"; then
  ok "setup.sh names where it moved the real skills path"
else
  ng "setup.sh skipped the real skills path silently"
fi

# (10) memory target は 2 本を一括で preflight する。
make_temp_root T8
make_fixture "$T8"
mkdir -p "${T8}/dotfiles/codex/memory"
echo keep >"${T8}/dotfiles/codex/memory/marker"
run_setup "$T8"
if [ ! -e "${T8}/dotfiles/claude/memory" ] && [ ! -L "${T8}/dotfiles/claude/memory" ] \
  && [ ! -L "${T8}/dotfiles/codex/memory" ] \
  && [ "$(cat "${T8}/dotfiles/codex/memory/marker" 2>/dev/null)" = keep ]; then
  ok "a real Codex memory path blocks changes to both memory targets"
else
  ng "a real Codex memory path did not leave both memory targets unchanged"
fi

make_temp_root T9
make_fixture "$T9"
mkdir -p "${T9}/foreign-memory"
echo keep >"${T9}/foreign-memory/marker"
ln -sfn "${T9}/foreign-memory" "${T9}/dotfiles/claude/memory"
run_setup "$T9"
if resolves_to "${T9}/dotfiles/claude/memory" "${T9}/foreign-memory" \
  && [ ! -e "${T9}/dotfiles/codex/memory" ] && [ ! -L "${T9}/dotfiles/codex/memory" ] \
  && [ "$(cat "${T9}/foreign-memory/marker" 2>/dev/null)" = keep ]; then
  ok "a foreign valid memory link blocks changes to both memory targets"
else
  ng "a foreign valid memory link did not leave both memory targets unchanged"
fi

# directory だけでなく regular file を指す valid link も foreign target として扱う。
# cd で解決すると file link と dangling を区別できず、誤って削除してしまう。
rm -f "${T9}/dotfiles/claude/memory"
echo keep >"${T9}/foreign-memory-file"
ln -sfn "${T9}/foreign-memory-file" "${T9}/dotfiles/claude/memory"
run_setup "$T9"
if resolves_to_file "${T9}/dotfiles/claude/memory" "${T9}/foreign-memory-file" \
  && [ ! -e "${T9}/dotfiles/codex/memory" ] && [ ! -L "${T9}/dotfiles/codex/memory" ] \
  && [ "$(cat "${T9}/foreign-memory-file" 2>/dev/null)" = keep ]; then
  ok "a foreign regular-file memory link blocks both memory targets"
else
  ng "a foreign regular-file memory link was overwritten or allowed the other target to change"
fi

make_temp_root T10
make_fixture "$T10"
ln -sfn "${T10}/gone-memory" "${T10}/dotfiles/claude/memory"
run_setup "$T10"
if resolves_to "${T10}/dotfiles/claude/memory" "${T10}/agent-memory" \
  && resolves_to "${T10}/dotfiles/codex/memory" "${T10}/agent-memory"; then
  ok "a dangling memory link is repaired without splitting the targets"
else
  ng "a dangling memory link did not converge both targets on canonical memory"
fi
if grep -q 'claude/memory was a dangling link to .*gone-memory' "${T10}/setup.log"; then
  ok "setup.sh reports the dangling memory target it discarded"
else
  ng "setup.sh repaired a dangling memory link without reporting its old target"
fi

# (11) 2 本目の symlink preparation が失敗しても、1 本目を先に本番 target へ
# 反映せず、両 target を元の missing 状態に保つ。memory 以外の ln は委譲する。
make_temp_root T11
make_fixture "$T11"
cat >"${T11}/bin/ln" <<'EOF'
#!/bin/sh
last=""
for arg in "$@"; do last="$arg"; done
case "$last" in
  "${FAIL_MEMORY_LINK_PREFIX}"*)
    printf 'injected ln failure: %s\n' "$last" >>"$SETUP_LN_LOG"
    exit 73
    ;;
esac
exec "$SETUP_SYSTEM_LN" "$@"
EOF
chmod +x "${T11}/bin/ln"
FAIL_MEMORY_LINK_PREFIX="${T11}/dotfiles/codex/memory" run_setup "$T11"
if grep -q '^injected ln failure:' "${T11}/ln.log"; then
  ok "the fixture injected the Codex memory link failure"
else
  ng "the fixture did not exercise the intended Codex memory link failure"
fi
if [ ! -e "${T11}/dotfiles/claude/memory" ] && [ ! -L "${T11}/dotfiles/claude/memory" ] \
  && [ ! -e "${T11}/dotfiles/codex/memory" ] && [ ! -L "${T11}/dotfiles/codex/memory" ] \
  && memory_setup_artifacts_absent "${T11}/dotfiles/claude" "${T11}/dotfiles/codex" \
  && grep -q 'could not prepare both memory links; targets unchanged' "${T11}/setup.log"; then
  ok "a second preparation failure leaves both memory targets unchanged and clean"
else
  ng "a second preparation failure left a changed target or setup artifact"
fi

# (12) 2 本目の switch が失敗したら、先に切り替えた 1 本目も missing へ戻す。
# wrapper は同じ destination の rollback move を妨げないよう 1 回だけ失敗する。
make_temp_root T12
make_fixture "$T12"
install_failing_mv "$T12"
FAIL_MEMORY_MOVE_TARGET="${T12}/dotfiles/codex/memory" run_setup "$T12"
if grep -q '^injected mv failure:' "${T12}/mv.log"; then
  ok "the fixture injected the second memory switch failure"
else
  ng "the fixture did not exercise the intended second memory switch failure"
fi
if [ ! -e "${T12}/dotfiles/claude/memory" ] && [ ! -L "${T12}/dotfiles/claude/memory" ] \
  && [ ! -e "${T12}/dotfiles/codex/memory" ] && [ ! -L "${T12}/dotfiles/codex/memory" ] \
  && memory_setup_artifacts_absent "${T12}/dotfiles/claude" "${T12}/dotfiles/codex" \
  && grep -q 'memory link switch failed; rolled back both targets' "${T12}/setup.log"; then
  ok "a second switch failure rolls both missing memory targets back cleanly"
else
  ng "a second switch failure did not restore both missing memory targets"
fi

# (13) dangling の prior state は存在有無だけでなく link literal まで同一に戻す。
make_temp_root T13
make_fixture "$T13"
claude_literal="${T13}/gone-claude-memory"
codex_literal="${T13}/gone-codex-memory"
ln -sfn "$claude_literal" "${T13}/dotfiles/claude/memory"
ln -sfn "$codex_literal" "${T13}/dotfiles/codex/memory"
install_failing_mv "$T13"
FAIL_MEMORY_MOVE_TARGET="${T13}/dotfiles/codex/memory" run_setup "$T13"
if grep -q '^injected mv failure:' "${T13}/mv.log"; then
  ok "the fixture injected the dangling-target switch failure"
else
  ng "the fixture did not exercise the dangling-target switch failure"
fi
if [ -L "${T13}/dotfiles/claude/memory" ] && [ ! -e "${T13}/dotfiles/claude/memory" ] \
  && [ "$(readlink "${T13}/dotfiles/claude/memory")" = "$claude_literal" ] \
  && [ -L "${T13}/dotfiles/codex/memory" ] && [ ! -e "${T13}/dotfiles/codex/memory" ] \
  && [ "$(readlink "${T13}/dotfiles/codex/memory")" = "$codex_literal" ] \
  && memory_setup_artifacts_absent "${T13}/dotfiles/claude" "${T13}/dotfiles/codex" \
  && grep -q 'memory link switch failed; rolled back both targets' "${T13}/setup.log"; then
  ok "a second switch failure restores both dangling link literals cleanly"
else
  ng "a second switch failure did not restore both dangling link literals"
fi

# (14) resolver の既存 directory は正しい agent-memory repository のみ許可する。
# canonical 判定に失敗しても、既存の dangling literal と missing target は変えない。
assert_invalid_memory_repository_is_non_destructive() {
  local root="$1" description="$2" literal
  literal="${root}/gone-memory"

  ln -sfn "$literal" "${root}/dotfiles/claude/memory"
  run_setup "$root"
  if [ -L "${root}/dotfiles/claude/memory" ] \
    && [ ! -e "${root}/dotfiles/claude/memory" ] \
    && [ "$(readlink "${root}/dotfiles/claude/memory")" = "$literal" ] \
    && [ ! -e "${root}/dotfiles/codex/memory" ] \
    && [ ! -L "${root}/dotfiles/codex/memory" ]; then
    ok "$description leaves both memory targets unchanged"
  else
    ng "$description changed a memory target"
  fi
}

make_temp_root T14
make_fixture "$T14"
rm -rf "${T14}/agent-memory/.git"
assert_invalid_memory_repository_is_non_destructive "$T14" "a plain directory"

make_temp_root T15
make_fixture "$T15"
rm -rf "${T15}/agent-memory/.git"
mkdir "${T15}/agent-memory/.git"
assert_invalid_memory_repository_is_non_destructive "$T15" "an empty .git directory"

make_temp_root T16
make_fixture "$T16"
"$SYSTEM_GIT" -C "${T16}/agent-memory" remote set-url origin \
  git@github.com:shishi/agent-memory-lookalike.git
assert_invalid_memory_repository_is_non_destructive "$T16" "a repository with a lookalike origin"

make_temp_root T31
make_fixture "$T31"
"$SYSTEM_GIT" -C "${T31}/agent-memory" remote set-url origin \
  https://github.com/shishi/agent-memory.git
run_setup "$T31"
if resolves_to "${T31}/dotfiles/claude/memory" "${T31}/agent-memory" \
  && resolves_to "${T31}/dotfiles/codex/memory" "${T31}/agent-memory"; then
  ok "the canonical HTTPS origin is accepted"
else
  ng "the canonical HTTPS origin was rejected"
fi

make_temp_root T32
make_fixture "$T32"
"$SYSTEM_GIT" -C "${T32}/agent-memory" remote set-url origin \
  ssh://git@github.com/shishi/agent-memory.git
run_setup "$T32"
if resolves_to "${T32}/dotfiles/claude/memory" "${T32}/agent-memory" \
  && resolves_to "${T32}/dotfiles/codex/memory" "${T32}/agent-memory"; then
  ok "the canonical SSH URL origin is accepted"
else
  ng "the canonical SSH URL origin was rejected"
fi

# (15) concurrent setup は同じHOME lockをatomicに競争し、一方だけがmemory
# transactionへ入る。旧実装では2processをfirst switch直前で同期させ、plain mvが
# directory symlinkを追ってcanonical repo内へtempを移す実raceを再現する。
make_temp_root T17
make_fixture "$T17"
install_concurrency_barriers "$T17"
export SETUP_MEMORY_LOCK="${T17}/home/.agent-memory-setup.lock"
export SETUP_LOCK_BARRIER="${T17}/barrier-lock"
export SETUP_MV_BARRIER="${T17}/barrier-mv"
export SETUP_CONCURRENT_MOVE_TARGET="${T17}/dotfiles/claude/memory"
run_setup "$T17" &
setup_pid_1=$!
run_setup "$T17" &
setup_pid_2=$!
wait "$setup_pid_1"
setup_status_1=$?
wait "$setup_pid_2"
setup_status_2=$?
unset SETUP_MEMORY_LOCK SETUP_LOCK_BARRIER SETUP_MV_BARRIER SETUP_CONCURRENT_MOVE_TARGET
if [ "$(count_barrier_tokens "${T17}/barrier-lock")" = 2 ] \
  && grep -q 'memory setup lock is busy' "${T17}/setup.log"; then
  ok "concurrent setup atomically admits one memory transaction and stops the other"
else
  ng "concurrent setup did not exercise an atomic memory lock conflict"
fi
if [ "$setup_status_1" -eq 0 ] && [ "$setup_status_2" -eq 0 ] \
  && resolves_to "${T17}/dotfiles/claude/memory" "${T17}/agent-memory" \
  && resolves_to "${T17}/dotfiles/codex/memory" "${T17}/agent-memory" \
  && memory_setup_artifacts_absent "${T17}/dotfiles/claude" "${T17}/dotfiles/codex" \
  && memory_setup_artifacts_absent "${T17}/agent-memory"; then
  ok "concurrent setup leaves both canonical links and no setup artifact"
else
  ng "concurrent setup changed a link or moved a setup artifact into canonical memory"
fi

# (16) rollback前に外部actorがこのprocessの設置linkを別linkへ置換した場合、
# changed flagだけを根拠に消してはいけない。literal/realpath ownership不一致を検出し、
# foreign linkを残してrollback incompleteを報告する。
make_temp_root T18
make_fixture "$T18"
mkdir -p "${T18}/foreign-memory"
install_failing_mv "$T18"
MUTATE_MEMORY_TARGET="${T18}/dotfiles/claude/memory" \
  MUTATE_MEMORY_LITERAL="${T18}/foreign-memory" \
  FAIL_MEMORY_MOVE_TARGET="${T18}/dotfiles/codex/memory" run_setup "$T18"
if resolves_to "${T18}/dotfiles/claude/memory" "${T18}/foreign-memory" \
  && [ ! -e "${T18}/dotfiles/codex/memory" ] \
  && [ ! -L "${T18}/dotfiles/codex/memory" ] \
  && grep -q 'rollback incomplete' "${T18}/setup.log"; then
  ok "rollback preserves a foreign link that replaced this process owned target"
else
  ng "rollback removed or overwrote a foreign replacement link"
fi

# (17) GNU/MSYS系は -T、macOS/BSD系は -h を選ぶ。fake uname が要求した option は
# 記録しつつ、recorder は実行hostの no-follow option へ翻訳してrename自体も行う。
make_temp_root T19
make_fixture "$T19"
install_recording_mv "$T19"
install_fake_uname "$T19" Linux
run_setup "$T19"
if grep -q '^-T -n ' "${T19}/move-options.log" \
  && resolves_to "${T19}/dotfiles/claude/memory" "${T19}/agent-memory" \
  && resolves_to "${T19}/dotfiles/codex/memory" "${T19}/agent-memory"; then
  ok "GNU or MSYS memory rename selects mv -T -n"
else
  ng "GNU or MSYS memory rename did not select mv -T -n"
fi

make_temp_root T20
make_fixture "$T20"
install_recording_mv "$T20"
install_fake_uname "$T20" Darwin
run_setup "$T20"
if grep -q '^-h -n ' "${T20}/move-options.log" \
  && resolves_to "${T20}/dotfiles/claude/memory" "${T20}/agent-memory" \
  && resolves_to "${T20}/dotfiles/codex/memory" "${T20}/agent-memory"; then
  ok "macOS or BSD memory rename selects mv -h -n"
else
  ng "macOS or BSD memory rename did not select mv -h -n"
fi

# revalidation後・rename直前にdestinationがdirectory symlinkへ変わっても、renameが
# symlinkをfollowしてcanonical repo内へsourceを入れ子にしないことを実動作で見る。
make_temp_root T21
make_fixture "$T21"
mkdir -p "${T21}/foreign-destination"
install_interleaving_mv "$T21"
INTERLEAVE_MOVE_TARGET="${T21}/dotfiles/claude/memory" \
  INTERLEAVE_MOVE_LITERAL="${T21}/foreign-destination" run_setup "$T21"
if resolves_to "${T21}/dotfiles/claude/memory" "${T21}/foreign-destination" \
  && [ ! -e "${T21}/dotfiles/codex/memory" ] \
  && memory_setup_artifacts_absent "${T21}/dotfiles/claude" "${T21}/dotfiles/codex" \
  && directory_is_empty "${T21}/foreign-destination" \
  && grep -q 'rollback incomplete' "${T21}/setup.log"; then
  ok "memory rename preserves an interposed foreign symlink"
else
  ng "memory rename overwrote or followed an interposed foreign symlink"
fi

make_temp_root T24
make_fixture "$T24"
install_interleaving_mv "$T24"
INTERLEAVE_MOVE_TARGET="${T24}/dotfiles/claude/memory" \
  INTERLEAVE_MOVE_KIND=file run_setup "$T24"
if [ ! -L "${T24}/dotfiles/claude/memory" ] \
  && [ "$(cat "${T24}/dotfiles/claude/memory" 2>/dev/null)" = keep ] \
  && [ ! -e "${T24}/dotfiles/codex/memory" ] \
  && memory_setup_artifacts_absent "${T24}/dotfiles/claude" "${T24}/dotfiles/codex" \
  && grep -q 'rollback incomplete' "${T24}/setup.log"; then
  ok "memory rename preserves an interposed regular file"
else
  ng "memory rename overwrote an interposed regular file"
fi

# detached dangling backupのliteralが変わった場合はtargetへ戻さず、その場に保存する。
make_temp_root T25
make_fixture "$T25"
original_backup_literal="${T25}/gone-original"
foreign_backup_literal="${T25}/gone-foreign"
ln -sfn "$original_backup_literal" "${T25}/dotfiles/claude/memory"
install_failing_mv "$T25"
MUTATE_MEMORY_BACKUP_PREFIX="${T25}/dotfiles/claude/memory.setup-" \
  MUTATE_MEMORY_BACKUP_LITERAL="$foreign_backup_literal" \
  FAIL_MEMORY_MOVE_TARGET="${T25}/dotfiles/codex/memory" run_setup "$T25"
backup_path="$(for path in "${T25}/dotfiles/claude"/memory.setup-*.back; do [ -L "$path" ] && { echo "$path"; break; }; done)"
if [ -n "$backup_path" ] && [ "$(readlink "$backup_path")" = "$foreign_backup_literal" ] \
  && [ ! -e "${T25}/dotfiles/claude/memory" ] \
  && [ ! -L "${T25}/dotfiles/claude/memory" ] \
  && grep -q 'rollback incomplete' "${T25}/setup.log"; then
  ok "rollback preserves a foreign replacement of the detached backup"
else
  ng "rollback moved or destroyed a foreign replacement backup"
fi

# backup cleanupが部分成功しても、削除済みと確認したown backupだけは保存literalから
# targetへ再生成し、2本ともtransaction前のdangling状態へ戻す。
make_temp_root T35
make_fixture "$T35"
claude_cleanup_literal="${T35}/gone-claude-cleanup"
codex_cleanup_literal="${T35}/gone-codex-cleanup"
ln -sfn "$claude_cleanup_literal" "${T35}/dotfiles/claude/memory"
ln -sfn "$codex_cleanup_literal" "${T35}/dotfiles/codex/memory"
install_failing_backup_rm "$T35"
FAIL_BACKUP_RM_PREFIX="${T35}/dotfiles/codex/memory.setup-" run_setup "$T35"
if grep -q '^injected backup rm failure:' "${T35}/rm.log" \
  && [ -L "${T35}/dotfiles/claude/memory" ] \
  && [ "$(readlink "${T35}/dotfiles/claude/memory")" = "$claude_cleanup_literal" ] \
  && [ -L "${T35}/dotfiles/codex/memory" ] \
  && [ "$(readlink "${T35}/dotfiles/codex/memory")" = "$codex_cleanup_literal" ] \
  && memory_setup_artifacts_absent "${T35}/dotfiles/claude" "${T35}/dotfiles/codex" \
  && memory_setup_artifacts_absent "${T35}/agent-memory" \
  && grep -q 'rolled back both targets' "${T35}/setup.log"; then
  ok "partial backup cleanup restores both prior dangling links without artifacts"
else
  ng "partial backup cleanup lost prior state or reported a false rollback"
fi

# canonical repositoryはcommitとHEAD内のrequired blobsを必須とする。
make_temp_root T26
make_fixture "$T26"
rm -rf "${T26}/agent-memory/.git"
"$SYSTEM_GIT" -C "${T26}/agent-memory" init -q
"$SYSTEM_GIT" -C "${T26}/agent-memory" branch -M main
"$SYSTEM_GIT" -C "${T26}/agent-memory" remote add origin git@github.com:shishi/agent-memory.git
assert_invalid_memory_repository_is_non_destructive "$T26" "a commitless repository"

make_temp_root T27
make_fixture "$T27"
"$SYSTEM_GIT" -C "${T27}/agent-memory" rm -q CONVENTIONS.md
"$SYSTEM_GIT" -C "${T27}/agent-memory" commit -qm 'remove conventions'
: >"${T27}/agent-memory/CONVENTIONS.md"
assert_invalid_memory_repository_is_non_destructive "$T27" "HEAD without a required memory blob"

make_temp_root T33
make_fixture "$T33"
"$SYSTEM_GIT" -C "${T33}/agent-memory" rm -q CONVENTIONS.md
mkdir "${T33}/agent-memory/CONVENTIONS.md"
: >"${T33}/agent-memory/CONVENTIONS.md/nested"
"$SYSTEM_GIT" -C "${T33}/agent-memory" add CONVENTIONS.md
"$SYSTEM_GIT" -C "${T33}/agent-memory" commit -qm 'replace conventions blob with tree'
assert_invalid_memory_repository_is_non_destructive "$T33" "HEAD with a required path that is not a blob"

# working treeのdirty/non-main/deleted状態はinjectorのdegraded判定へ委譲する。
make_temp_root T28
make_fixture "$T28"
"$SYSTEM_GIT" -C "${T28}/agent-memory" checkout -qb work-in-progress
rm "${T28}/agent-memory/MEMORY.md" "${T28}/agent-memory/CONVENTIONS.md"
echo dirty >"${T28}/agent-memory/uncommitted"
run_setup "$T28"
if resolves_to "${T28}/dotfiles/claude/memory" "${T28}/agent-memory" \
  && resolves_to "${T28}/dotfiles/codex/memory" "${T28}/agent-memory"; then
  ok "committed canonical memory links despite dirty non-main deleted working files"
else
  ng "validator incorrectly gated on working tree state"
fi

# owner token一致時はTERMでlockを解放し、foreign tokenへ変わったlockは残す。
make_temp_root T29
make_fixture "$T29"
install_signal_blocking_git "$T29"
start_setup_for_signal "$T29"
signal_pid="$SIGNAL_SETUP_PID"
wait_for_file "${T29}/signal.ready"
kill -TERM "$signal_pid"
wait "$signal_pid"
signal_status=$?
if [ "$signal_status" -ne 0 ] \
  && [ ! -e "${T29}/home/.agent-memory-setup.lock" ] \
  && [ ! -e "${T29}/dotfiles/claude/memory" ] \
  && [ ! -L "${T29}/dotfiles/claude/memory" ] \
  && [ ! -e "${T29}/dotfiles/codex/memory" ] \
  && [ ! -L "${T29}/dotfiles/codex/memory" ]; then
  ok "TERM releases a lock still owned by this setup process"
else
  ng "TERM leaked this process memory lock, continued memory setup, or returned success"
fi

make_temp_root T34
make_fixture "$T34"
install_signal_blocking_git "$T34"
start_setup_for_int "$T34"
signal_pid="$SIGNAL_SETUP_PID"
wait_for_file "${T34}/signal.ready"
kill -INT "$signal_pid"
wait "$signal_pid"
signal_status=$?
if [ "$signal_status" -eq 130 ] \
  && [ ! -e "${T34}/home/.agent-memory-setup.lock" ] \
  && [ ! -e "${T34}/dotfiles/claude/memory" ] \
  && [ ! -L "${T34}/dotfiles/claude/memory" ] \
  && [ ! -e "${T34}/dotfiles/codex/memory" ] \
  && [ ! -L "${T34}/dotfiles/codex/memory" ]; then
  ok "INT exits 130 and releases a lock still owned by this setup process"
else
  ng "INT continued memory setup, did not exit 130, or leaked this process memory lock"
fi

# memory transactionの最初のswitch直後にTERMを受けても、中間状態で終了せず、
# transactionを完了してからlockを解放しsignal statusを返す。
make_temp_root T36
make_fixture "$T36"
install_signaling_mv "$T36"
SIGNAL_AFTER_MOVE_TARGET="${T36}/dotfiles/claude/memory" run_setup "$T36"
signal_status=$?
if [ "$signal_status" -eq 143 ] \
  && { { resolves_to "${T36}/dotfiles/claude/memory" "${T36}/agent-memory" \
      && resolves_to "${T36}/dotfiles/codex/memory" "${T36}/agent-memory"; } \
    || { [ ! -e "${T36}/dotfiles/claude/memory" ] \
      && [ ! -L "${T36}/dotfiles/claude/memory" ] \
      && [ ! -e "${T36}/dotfiles/codex/memory" ] \
      && [ ! -L "${T36}/dotfiles/codex/memory" ]; }; } \
  && memory_setup_artifacts_absent "${T36}/dotfiles/claude" "${T36}/dotfiles/codex" \
  && memory_setup_artifacts_absent "${T36}/agent-memory" \
  && [ ! -e "${T36}/home/.agent-memory-setup.lock" ]; then
  ok "TERM during memory switch exits 143 after reaching a consistent state"
else
  ng "TERM during memory switch left a split or dirty transaction state"
fi

# validatorの最終git検査後にrepoが消えた場合、空のcanonical realpathをdanglingの
# 期待値として扱わず、temp/targetに触れる前にfail closedする。
make_temp_root T37
make_fixture "$T37"
install_repo_moving_git "$T37"
install_recording_memory_ln "$T37"
MOVE_REPO_SOURCE="${T37}/agent-memory" MOVE_REPO_DEST="${T37}/moved-agent-memory" \
  run_setup "$T37"
if [ -d "${T37}/moved-agent-memory/.git" ] \
  && [ ! -e "${T37}/agent-memory" ] \
  && [ ! -e "${T37}/dotfiles/claude/memory" ] \
  && [ ! -L "${T37}/dotfiles/claude/memory" ] \
  && [ ! -e "${T37}/dotfiles/codex/memory" ] \
  && [ ! -L "${T37}/dotfiles/codex/memory" ] \
  && memory_setup_artifacts_absent "${T37}/dotfiles/claude" "${T37}/dotfiles/codex" \
  && memory_setup_artifacts_absent "${T37}/moved-agent-memory" \
  && [ ! -s "${T37}/ln.log" ] \
  && [ ! -e "${T37}/home/.agent-memory-setup.lock" ] \
  && grep -q 'could not resolve canonical agent-memory repository' "${T37}/setup.log"; then
  ok "repository disappearance after validation is non-destructive"
else
  ng "repository disappearance was accepted as an empty canonical target"
fi

make_temp_root T30
make_fixture "$T30"
install_signal_blocking_git "$T30"
SIGNAL_FOREIGN_OWNER=foreign-owner start_setup_for_signal "$T30"
signal_pid="$SIGNAL_SETUP_PID"
wait_for_file "${T30}/signal.ready"
kill -TERM "$signal_pid"
wait "$signal_pid"
signal_status=$?
if [ "$signal_status" -ne 0 ] \
  && [ "$(cat "${T30}/home/.agent-memory-setup.lock/owner" 2>/dev/null)" = foreign-owner ]; then
  ok "TERM does not delete a lock whose owner token changed"
else
  ng "TERM deleted a foreign owner lock or returned success"
fi

# (18) stale lockは所有権を証明できないので削除せず、明示停止する。
make_temp_root T22
make_fixture "$T22"
mkdir "${T22}/home/.agent-memory-setup.lock"
echo keep >"${T22}/home/.agent-memory-setup.lock/owner"
run_setup "$T22"
if [ "$(cat "${T22}/home/.agent-memory-setup.lock/owner" 2>/dev/null)" = keep ] \
  && [ ! -e "${T22}/dotfiles/claude/memory" ] \
  && [ ! -L "${T22}/dotfiles/claude/memory" ] \
  && [ ! -e "${T22}/dotfiles/codex/memory" ] \
  && [ ! -L "${T22}/dotfiles/codex/memory" ] \
  && grep -q 'memory setup lock is busy' "${T22}/setup.log"; then
  ok "a stale memory lock is preserved and stops the transaction"
else
  ng "setup removed a stale lock or changed a memory target"
fi

# clone commandがsuccessでも結果を信用せず、既存repoと同じvalidatorへ通す。
make_temp_root T23
make_fixture "$T23"
rm -rf "${T23}/agent-memory"
cat >"${T23}/bin/git" <<'EOF'
#!/bin/sh
if [ "${1:-}" = clone ]; then
  last=""
  for arg in "$@"; do last="$arg"; done
  "$SETUP_SYSTEM_MKDIR" -p "$last"
  : >"$last/MEMORY.md"
  : >"$last/CONVENTIONS.md"
  printf 'simulated invalid clone\n' >>"$SETUP_EXTERNAL_CALL_LOG"
  exit 0
fi
exec "$SETUP_SYSTEM_GIT" "$@"
EOF
chmod +x "${T23}/bin/git"
run_setup "$T23"
if grep -q 'simulated invalid clone' "${T23}/external-calls.log" \
  && [ ! -e "${T23}/dotfiles/claude/memory" ] \
  && [ ! -L "${T23}/dotfiles/claude/memory" ] \
  && [ ! -e "${T23}/dotfiles/codex/memory" ] \
  && [ ! -L "${T23}/dotfiles/codex/memory" ] \
  && grep -q 'not the canonical agent-memory repository' "${T23}/setup.log"; then
  ok "an invalid successful clone is rejected before linking"
else
  ng "setup trusted an invalid successful clone"
fi

# (19) XDG 配下の設定リンク。agent home と違い runtime を持たないので repo 版で
# 上書きしてよいが、リンクの形は同じ規則で張られること。
make_temp_root T7
make_fixture "$T7"
mkdir -p "${T7}/dotfiles/wezterm" "${T7}/dotfiles/fish" "${T7}/dotfiles/nvim" \
  "${T7}/dotfiles/helix"
run_setup "$T7"
# wezterm と emacs は REMOTE_CONTAINERS ゲートの内側にあり、この fixture
# (emacs の clone を避けるため true) では走らない。ゲート外の 3 つで見る。
config_dirs_ok=1
for d in fish nvim helix; do
  resolves_to "${T7}/config/$d" "${T7}/dotfiles/$d" || config_dirs_ok=0
done
if [ "$config_dirs_ok" = 1 ]; then
  ok "fish / nvim / helix link into the checkout"
else
  ng "a config directory link is missing or points elsewhere"
fi

# nushell はディレクトリではなく中の 2 ファイルを張る。~/.config/nushell 自体が
# リンクになってしまうと、nushell は config.nu の中身を env.nu として読む。
if [ -d "${T7}/config/nushell" ] && [ ! -L "${T7}/config/nushell" ] \
  && resolves_to_file "${T7}/config/nushell/config.nu" "${T7}/dotfiles/nushell/config.nu" \
  && resolves_to_file "${T7}/config/nushell/env.nu" "${T7}/dotfiles/nushell/env.nu"; then
  ok "nushell keeps a real directory holding one link per file"
else
  ng "nushell is not a directory of per-file links"
fi

# 既にディレクトリを指すリンクが在るときも張り替わること。ln -sf は既存の dir
# symlink を辿って中に張るので、-n が無いと ${d}/${d} ができて元のリンクが残る。
mkdir -p "${T7}/other/fish"
ln -sfn "${T7}/other/fish" "${T7}/config/fish"
run_setup "$T7"
if resolves_to "${T7}/config/fish" "${T7}/dotfiles/fish" \
  && [ ! -e "${T7}/other/fish/fish" ]; then
  ok "a config link pointing elsewhere is repointed, not nested inside"
else
  ng "setup.sh nested a link inside the old target instead of replacing it"
fi

# nushell が symlink になっていたら実ディレクトリへ戻す。Nushell は history を同じ
# 場所へ書くので、指し先が repo でも他所でも、生成物の置き場がリンク越しになる。
# リンク先は source 以外にする。source 自身を指させると「中の 2 ファイルを張る」が
# source を自分で置換する退化した操作になり、何を測っているのか判らなくなる。
rm -rf "${T7}/config/nushell"
mkdir -p "${T7}/other/nushell"
ln -sfn "${T7}/other/nushell" "${T7}/config/nushell"
run_setup "$T7"
if [ ! -L "${T7}/config/nushell" ] && [ -d "${T7}/config/nushell" ] \
  && resolves_to_file "${T7}/config/nushell/config.nu" "${T7}/dotfiles/nushell/config.nu" \
  && resolves_to_file "${T7}/config/nushell/env.nu" "${T7}/dotfiles/nushell/env.nu"; then
  ok "a symlinked nushell directory becomes real, holding both per-file links"
else
  ng "nushell stayed a symlink, or its per-file links are missing"
fi

# (20) Hunk が同梱する既定の review skill を、コピーせず Claude/Codex の
# personal skill として読む。Hunk 更新後の setup 再実行で新しい同梱版へ追随できる。
make_temp_root T38
make_fixture "$T38"
mkdir -p "${T38}/hunk-review-v1" "${T38}/hunk-review-v2"
: >"${T38}/hunk-review-v1/SKILL.md"
: >"${T38}/hunk-review-v2/SKILL.md"
printf '%s\n' "${T38}/hunk-review-v1/SKILL.md" >"${T38}/hunk-skill-path"
cat >"${T38}/bin/hunk" <<'EOF'
#!/bin/sh
if [ "$*" = "skill path hunk-review" ]; then
  cat "$HOME/../hunk-skill-path"
  exit 0
fi
exit 64
EOF
chmod +x "${T38}/bin/hunk"
run_setup "$T38"
if resolves_to_file "${T38}/home/.claude/skills/hunk-review/SKILL.md" \
  "${T38}/hunk-review-v1/SKILL.md" \
  && resolves_to_file "${T38}/home/.agents/skills/hunk-review/SKILL.md" \
    "${T38}/hunk-review-v1/SKILL.md"; then
  ok "Hunk's bundled review skill is available to Claude and Codex"
else
  ng "Hunk's bundled review skill is not available to both agents"
fi
printf '%s\n' "${T38}/hunk-review-v2/SKILL.md" >"${T38}/hunk-skill-path"
run_setup "$T38"
if resolves_to_file "${T38}/home/.claude/skills/hunk-review/SKILL.md" \
  "${T38}/hunk-review-v2/SKILL.md" \
  && resolves_to_file "${T38}/home/.agents/skills/hunk-review/SKILL.md" \
    "${T38}/hunk-review-v2/SKILL.md"; then
  ok "re-running setup follows an updated bundled Hunk skill"
else
  ng "re-running setup did not follow the updated bundled Hunk skill"
fi

# (21) skill directory 自体が symlink でも外部を辿って書き換えない。setup が管理する
# リンクだけを置き換え、リンク先にある既存 SKILL.md は保持する。
make_temp_root T39
make_fixture "$T39"
mkdir -p "${T39}/hunk-review" "${T39}/external-claude-hunk" \
  "${T39}/external-codex-hunk" "${T39}/dotfiles/claude/skills"
: >"${T39}/hunk-review/SKILL.md"
printf 'keep-claude\n' >"${T39}/external-claude-hunk/SKILL.md"
printf 'keep-codex\n' >"${T39}/external-codex-hunk/SKILL.md"
ln -s "${T39}/external-claude-hunk" \
  "${T39}/dotfiles/claude/skills/hunk-review"
ln -s "${T39}/external-codex-hunk" \
  "${T39}/dotfiles/codex/skills/hunk-review"
cat >"${T39}/bin/hunk" <<'EOF'
#!/bin/sh
if [ "$*" = "skill path hunk-review" ]; then
  printf '%s\n' "$HOME/../hunk-review/SKILL.md"
  exit 0
fi
exit 64
EOF
chmod +x "${T39}/bin/hunk"
run_setup "$T39"
if [ ! -L "${T39}/external-claude-hunk/SKILL.md" ] \
  && [ "$(cat "${T39}/external-claude-hunk/SKILL.md")" = keep-claude ] \
  && [ ! -L "${T39}/external-codex-hunk/SKILL.md" ] \
  && [ "$(cat "${T39}/external-codex-hunk/SKILL.md")" = keep-codex ] \
  && resolves_to_file "${T39}/home/.claude/skills/hunk-review/SKILL.md" \
    "${T39}/hunk-review/SKILL.md" \
  && resolves_to_file "${T39}/home/.agents/skills/hunk-review/SKILL.md" \
    "${T39}/hunk-review/SKILL.md"; then
  ok "Hunk skill setup replaces parent links without modifying their targets"
else
  ng "Hunk skill setup followed a parent link or failed to install the bundled skill"
fi

# (22) optional integration は component header、indented detail、result の順で出す。
# Herdr の fallback 経路は収束済みなら書き込まない(herdr の installer は tracked
# 設定と別形式の hook エントリを追加するため、healthy な機で毎回 diff を作らせない)。
make_temp_root T40
make_fixture "$T40"
mkdir -p "${T40}/hunk-review"
: >"${T40}/hunk-review/SKILL.md"
write_herdr_hook_configs "$T40"
cat >"${T40}/dotfiles/claude/install-plugins.sh" <<'EOF'
#!/bin/sh
printf 'install-plugins: detail\n'
printf '%s\n' "${INSTALL_PLUGINS_SUMMARY:-unset}" >"$HOME/../plugin-summary"
exit 0
EOF
cat >"${T40}/bin/claude" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"${T40}/bin/herdr" <<'EOF'
#!/bin/sh
case "$*" in
  "integration install claude")
    printf 'claude\n' >>"$HOME/../herdr-installs"
    printf 'claude: unchanged\n'
    exit 0
    ;;
  "integration install codex")
    printf 'codex\n' >>"$HOME/../herdr-installs"
    printf 'codex: unchanged\n'
    exit 0
    ;;
  "integration status")
    printf 'claude: current (v8) (%s/.claude/hooks/herdr-agent-state.sh)\n' "$HOME"
    printf 'codex: current (v8) (%s/.codex/herdr-agent-state.sh)\n' "$HOME"
    exit 0
    ;;
esac
exit 64
EOF
cat >"${T40}/bin/hunk" <<'EOF'
#!/bin/sh
if [ "$*" = "skill path hunk-review" ]; then
  printf '%s\n' "$HOME/../hunk-review/SKILL.md"
  exit 0
fi
exit 64
EOF
chmod +x "${T40}/dotfiles/claude/install-plugins.sh" "${T40}/bin/claude" \
  "${T40}/bin/herdr" "${T40}/bin/hunk"
write_hide_herdr_bootstrap "$T40"
SETUP_BASH_ENV="${T40}/hide-herdr-bootstrap.sh" run_setup "$T40"
if [ "$(component_log_block "${T40}/setup.log" claude-plugins)" = \
    $'setup.sh: claude-plugins\n  install-plugins: detail\n  result: ok' ] \
  && [ "$(component_log_block "${T40}/setup.log" herdr-integrations)" = \
    $'setup.sh: herdr-integrations\n  result: ok' ] \
  && [ "$(component_log_block "${T40}/setup.log" hunk-review-skills)" = \
    $'setup.sh: hunk-review-skills\n  result: ok' ] \
  && [ "$(cat "${T40}/plugin-summary")" = 0 ] \
  && [ ! -e "${T40}/herdr-installs" ]; then
  ok "a converged Herdr fallback succeeds without calling install"
else
  ng "a converged Herdr fallback ran install or logged inconsistently"
fi

# (23) optional integration が失敗しても、同じ階層形式で出して setup は継続する。
make_temp_root T41
make_fixture "$T41"
printf '{}\n' >"${T41}/dotfiles/claude/settings.json"
cat >"${T41}/dotfiles/claude/install-plugins.sh" <<'EOF'
#!/bin/sh
printf 'install-plugins: failed detail\n' >&2
exit 41
EOF
cat >"${T41}/bin/claude" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"${T41}/bin/herdr" <<'EOF'
#!/bin/sh
case "$*" in
  "integration install claude")
    printf 'herdr: failed detail\n' >&2
    exit 42
    ;;
  "integration status")
    printf 'claude: not installed (%s/.claude/hooks/herdr-agent-state.sh)\n' "$HOME"
    printf 'codex: not installed (%s/.codex/herdr-agent-state.sh)\n' "$HOME"
    exit 0
    ;;
esac
exit 64
EOF
cat >"${T41}/bin/hunk" <<'EOF'
#!/bin/sh
if [ "$*" = "skill path hunk-review" ]; then
  printf '/nonexistent/hunk-review/SKILL.md\n'
  exit 0
fi
exit 64
EOF
chmod +x "${T41}/dotfiles/claude/install-plugins.sh" "${T41}/bin/claude" \
  "${T41}/bin/herdr" "${T41}/bin/hunk"
write_hide_herdr_bootstrap "$T41"
SETUP_BASH_ENV="${T41}/hide-herdr-bootstrap.sh" run_setup "$T41"
if [ "$(component_log_block "${T41}/setup.log" claude-plugins)" = \
    $'setup.sh: claude-plugins\n  install-plugins: failed detail\n  result: failed (continuing)' ] \
  && [ "$(component_log_block "${T41}/setup.log" herdr-integrations)" = \
    $'setup.sh: herdr-integrations\n  herdr: failed detail\n  result: failed (continuing)' ] \
  && [ "$(component_log_block "${T41}/setup.log" hunk-review-skills)" = \
    $'setup.sh: hunk-review-skills\n  hunk-review skill path is unavailable (continuing)\n  result: failed (continuing)' ]; then
  ok "failed integrations log header, indented details, then result"
else
  ng "failed integration logs are not ordered or nested consistently"
fi

# (24) optional command が無い環境でも、header の下に skip の理由を出す。
make_temp_root T42
make_fixture "$T42"
cat >"${T42}/hide-integrations.sh" <<'EOF'
command() {
  if [ "${1:-}" = -v ]; then
    case "${2:-}" in
      claude | herdr | herdr-bootstrap | hunk) return 1 ;;
    esac
  fi
  builtin command "$@"
}
EOF
SETUP_BASH_ENV="${T42}/hide-integrations.sh" run_setup "$T42"
if [ "$(component_log_block "${T42}/setup.log" claude-plugins)" = \
    $'setup.sh: claude-plugins\n  result: skipped (claude not found)' ] \
  && [ "$(component_log_block "${T42}/setup.log" herdr-integrations)" = \
    $'setup.sh: herdr-integrations\n  result: skipped (herdr not found)' ] \
  && [ "$(component_log_block "${T42}/setup.log" hunk-review-skills)" = \
    $'setup.sh: hunk-review-skills\n  result: skipped (hunk not found)' ]; then
  ok "missing integrations log header followed by skipped result"
else
  ng "missing integration logs are not ordered consistently"
fi

# (25) Claude CLI だけあっても、installer の前提が無ければ ok と誤報告しない。
make_temp_root T43
make_fixture "$T43"
printf '{}\n' >"${T43}/dotfiles/claude/settings.json"
cat >"${T43}/bin/claude" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "${T43}/bin/claude"
cat >"${T43}/hide-jq.sh" <<'EOF'
command() {
  if [ "${1:-}" = -v ]; then
    case "${2:-}" in
      jq | herdr | herdr-bootstrap | hunk) return 1 ;;
    esac
  fi
  builtin command "$@"
}
EOF
SETUP_BASH_ENV="${T43}/hide-jq.sh" run_setup "$T43"
if [ "$(component_log_block "${T43}/setup.log" claude-plugins)" = \
    $'setup.sh: claude-plugins\n  result: skipped (jq not found)' ]; then
  ok "a missing jq prerequisite reports Claude plugins as skipped"
else
  ng "a missing jq prerequisite is reported as Claude plugin success"
fi

make_temp_root T44
make_fixture "$T44"
cat >"${T44}/bin/claude" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "${T44}/bin/claude"
cat >"${T44}/hide-other-integrations.sh" <<'EOF'
command() {
  if [ "${1:-}" = -v ]; then
    case "${2:-}" in
      herdr | herdr-bootstrap | hunk) return 1 ;;
    esac
  fi
  builtin command "$@"
}
EOF
SETUP_BASH_ENV="${T44}/hide-other-integrations.sh" run_setup "$T44"
if [ "$(component_log_block "${T44}/setup.log" claude-plugins)" = \
    $'setup.sh: claude-plugins\n  result: skipped (settings.json not found)' ]; then
  ok "a missing settings.json prerequisite reports Claude plugins as skipped"
else
  ng "a missing settings.json prerequisite is reported as Claude plugin success"
fi

# (26) install が 0 でも status が current でなければ Herdr 成功にはしない。
make_temp_root T45
make_fixture "$T45"
write_herdr_hook_configs "$T45"
cat >"${T45}/bin/claude" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"${T45}/bin/herdr" <<'EOF'
#!/bin/sh
case "$*" in
  "integration install claude" | "integration install codex") exit 0 ;;
  "integration status")
    printf 'claude: current (v8) (%s/.claude/hooks/herdr-agent-state.sh)\n' "$HOME"
    printf 'codex: stale (v7) (%s/.codex/herdr-agent-state.sh)\n' "$HOME"
    exit 0
    ;;
esac
exit 64
EOF
chmod +x "${T45}/bin/claude" "${T45}/bin/herdr"
write_hide_herdr_bootstrap "$T45"
SETUP_BASH_ENV="${T45}/hide-herdr-bootstrap.sh" run_setup "$T45"
if [ "$(component_log_block "${T45}/setup.log" herdr-integrations)" = \
    $'setup.sh: herdr-integrations\n  result: failed (continuing)' ]; then
  ok "a stale Herdr postcondition is reported as failed"
else
  ng "a stale Herdr postcondition is reported as successful"
fi

# (27) detail formatter が失敗した場合は、子が成功しても component を成功にしない。
make_temp_root T46
make_fixture "$T46"
printf '{}\n' >"${T46}/dotfiles/claude/settings.json"
cat >"${T46}/dotfiles/claude/install-plugins.sh" <<'EOF'
#!/bin/sh
printf 'install-plugins: detail that cannot be formatted\n'
exit 0
EOF
cat >"${T46}/bin/claude" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"${T46}/bin/sed" <<'EOF'
#!/bin/sh
exit 7
EOF
chmod +x "${T46}/dotfiles/claude/install-plugins.sh" "${T46}/bin/claude" \
  "${T46}/bin/sed"
write_hide_herdr_all "$T46"
SETUP_BASH_ENV="${T46}/hide-herdr-all.sh" run_setup "$T46"
if [ "$(component_log_block "${T46}/setup.log" claude-plugins)" = \
    $'setup.sh: claude-plugins\n  output formatting failed (exit 7)\n  result: failed (continuing)' ]; then
  ok "a formatter failure prevents a false successful result"
else
  ng "a formatter failure is hidden behind a successful result"
fi

# (28) 子が signal で終了しても pipeline の formatter status で成功にしない。
make_temp_root T47
make_fixture "$T47"
printf '{}\n' >"${T47}/dotfiles/claude/settings.json"
cat >"${T47}/dotfiles/claude/install-plugins.sh" <<'EOF'
#!/bin/sh
printf 'install-plugins: interrupted detail\n' >&2
kill -TERM $$
EOF
cat >"${T47}/bin/claude" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "${T47}/dotfiles/claude/install-plugins.sh" "${T47}/bin/claude"
write_hide_herdr_all "$T47"
SETUP_BASH_ENV="${T47}/hide-herdr-all.sh" run_setup "$T47"
if [ "$(component_log_block "${T47}/setup.log" claude-plugins)" = \
    $'setup.sh: claude-plugins\n  install-plugins: interrupted detail\n  result: failed (continuing)' ]; then
  ok "a signaled child keeps stderr detail and a failed result"
else
  ng "a signaled child lost stderr detail or reported success"
fi

# (29) marker と同じ文字列があっても、hook object でなければ後条件を満たさない。
make_temp_root T48
make_fixture "$T48"
printf '{"note":"herdr-agent-state.sh"}\n' >"${T48}/dotfiles/claude/settings.json"
printf '{"note":"herdr-agent-state.sh"}\n' >"${T48}/dotfiles/codex/hooks.json"
cat >"${T48}/bin/claude" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"${T48}/bin/herdr" <<'EOF'
#!/bin/sh
case "$*" in
  "integration install claude" | "integration install codex") exit 0 ;;
  "integration status")
    printf 'claude: current (v8) (%s/.claude/hooks/herdr-agent-state.sh)\n' "$HOME"
    printf 'codex: current (v8) (%s/.codex/herdr-agent-state.sh)\n' "$HOME"
    exit 0
    ;;
esac
exit 64
EOF
chmod +x "${T48}/bin/claude" "${T48}/bin/herdr"
write_hide_herdr_bootstrap "$T48"
SETUP_BASH_ENV="${T48}/hide-herdr-bootstrap.sh" run_setup "$T48"
if [ "$(component_log_block "${T48}/setup.log" herdr-integrations)" = \
    $'setup.sh: herdr-integrations\n  result: failed (continuing)' ]; then
  ok "marker text outside a hook object does not satisfy Herdr postconditions"
else
  ng "marker text outside a hook object is accepted as a Herdr hook"
fi

# (30) 壊れた JSON は marker 文字列を含んでいても後条件を満たさない。
make_temp_root T49
make_fixture "$T49"
printf 'herdr-agent-state.sh\n' >"${T49}/dotfiles/claude/settings.json"
printf 'herdr-agent-state.sh\n' >"${T49}/dotfiles/codex/hooks.json"
cat >"${T49}/bin/claude" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"${T49}/bin/herdr" <<'EOF'
#!/bin/sh
case "$*" in
  "integration install claude" | "integration install codex") exit 0 ;;
  "integration status")
    printf 'claude: current (v8) (%s/.claude/hooks/herdr-agent-state.sh)\n' "$HOME"
    printf 'codex: current (v8) (%s/.codex/herdr-agent-state.sh)\n' "$HOME"
    exit 0
    ;;
esac
exit 64
EOF
chmod +x "${T49}/bin/claude" "${T49}/bin/herdr"
write_hide_herdr_bootstrap "$T49"
SETUP_BASH_ENV="${T49}/hide-herdr-bootstrap.sh" run_setup "$T49"
if [ "$(component_log_block "${T49}/setup.log" herdr-integrations)" = \
    $'setup.sh: herdr-integrations\n  result: failed (continuing)' ]; then
  ok "invalid JSON does not satisfy Herdr postconditions"
else
  ng "invalid JSON is accepted as a Herdr hook configuration"
fi

# (31) 未収束の fallback は herdr integration install で収束させてから成功にする。
# fake の install は herdr 実機の挙動(絶対パス形式の hook エントリ)を書く。
make_temp_root T51
make_fixture "$T51"
printf '{}\n' >"${T51}/dotfiles/claude/settings.json"
printf '{}\n' >"${T51}/dotfiles/codex/hooks.json"
cat >"${T51}/bin/herdr" <<'EOF'
#!/bin/sh
case "$*" in
  "integration install claude")
    printf 'claude\n' >>"$HOME/../herdr-installs"
    printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash '\''%s/.claude/hooks/herdr-agent-state.sh'\'' session"}]}]}}\n' \
      "$HOME" >"$HOME/.claude/settings.json"
    printf 'claude: installed\n'
    exit 0
    ;;
  "integration install codex")
    printf 'codex\n' >>"$HOME/../herdr-installs"
    printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash '\''%s/.codex/herdr-agent-state.sh'\'' session"}]}]}}\n' \
      "$HOME" >"$HOME/.codex/hooks.json"
    printf 'codex: installed\n'
    exit 0
    ;;
  "integration status")
    printf 'claude: current (v8) (%s/.claude/hooks/herdr-agent-state.sh)\n' "$HOME"
    printf 'codex: current (v8) (%s/.codex/herdr-agent-state.sh)\n' "$HOME"
    exit 0
    ;;
esac
exit 64
EOF
chmod +x "${T51}/bin/herdr"
write_hide_herdr_bootstrap "$T51"
SETUP_BASH_ENV="${T51}/hide-herdr-bootstrap.sh" run_setup "$T51"
if [ "$(component_log_block "${T51}/setup.log" herdr-integrations)" = \
    $'setup.sh: herdr-integrations\n  claude: installed\n  codex: installed\n  result: ok' ] \
  && [ "$(cat "${T51}/herdr-installs")" = $'claude\ncodex' ]; then
  ok "an unconverged Herdr fallback installs and then reports success"
else
  ng "an unconverged Herdr fallback failed to install or misreported"
fi

# (32) herdr-bootstrap があればそれを優先し、herdr integration install は呼ばない。
make_temp_root T50
make_fixture "$T50"
write_herdr_hook_configs "$T50"
cat >"${T50}/bin/herdr-bootstrap" <<'EOF'
#!/bin/sh
printf '%s\n' "${INSTALL_PLUGINS_QUIET:-unset}" >"$HOME/../herdr-quiet"
printf 'unchanged: herdr detail\n'
exit 0
EOF
cat >"${T50}/bin/herdr" <<'EOF'
#!/bin/sh
case "$*" in
  "integration install"*)
    printf '%s\n' "$*" >>"$HOME/../herdr-installs"
    exit 0
    ;;
  "integration status")
    printf 'claude: current (v8) (%s/.claude/hooks/herdr-agent-state.sh)\n' "$HOME"
    printf 'codex: current (v8) (%s/.codex/herdr-agent-state.sh)\n' "$HOME"
    exit 0
    ;;
esac
exit 64
EOF
chmod +x "${T50}/bin/herdr-bootstrap" "${T50}/bin/herdr"
run_setup "$T50"
if [ "$(component_log_block "${T50}/setup.log" herdr-integrations)" = \
    $'setup.sh: herdr-integrations\n  unchanged: herdr detail\n  result: ok' ] \
  && [ "$(cat "${T50}/herdr-quiet")" = 1 ] \
  && [ ! -e "${T50}/herdr-installs" ]; then
  ok "herdr-bootstrap takes precedence and direct install is not called"
else
  ng "herdr-bootstrap precedence is broken or direct install ran anyway"
fi

# (33) fallback は jq が無ければ検証できないため、書き込む前に skip する。
make_temp_root T52
make_fixture "$T52"
write_herdr_hook_configs "$T52"
cat >"${T52}/bin/herdr" <<'EOF'
#!/bin/sh
case "$*" in
  "integration install"*)
    printf '%s\n' "$*" >>"$HOME/../herdr-installs"
    exit 0
    ;;
  "integration status")
    printf 'claude: current (v8) (%s/.claude/hooks/herdr-agent-state.sh)\n' "$HOME"
    printf 'codex: current (v8) (%s/.codex/herdr-agent-state.sh)\n' "$HOME"
    exit 0
    ;;
esac
exit 64
EOF
chmod +x "${T52}/bin/herdr"
cat >"${T52}/hide-jq-and-bootstrap.sh" <<'EOF'
command() {
  if [ "${1:-}" = -v ]; then
    case "${2:-}" in
      jq | herdr-bootstrap) return 1 ;;
    esac
  fi
  builtin command "$@"
}
EOF
SETUP_BASH_ENV="${T52}/hide-jq-and-bootstrap.sh" run_setup "$T52"
if [ "$(component_log_block "${T52}/setup.log" herdr-integrations)" = \
    $'setup.sh: herdr-integrations\n  result: skipped (jq not found)' ] \
  && [ ! -e "${T52}/herdr-installs" ]; then
  ok "a jq-less Herdr fallback skips before writing anything"
else
  ng "a jq-less Herdr fallback wrote or misreported"
fi

# (34) herdr が期待する hook 配置が tracked 構成と違うなら installer を呼ばない。
# Windows 版 herdr は PowerShell hook (.ps1) を書き、HERDR_INTEGRATION_ID を含む
# 既存の .sh を削除するため、配置不一致での install は tracked hook を壊す。
make_temp_root T53
make_fixture "$T53"
write_herdr_hook_configs "$T53"
cat >"${T53}/bin/herdr" <<'EOF'
#!/bin/sh
case "$*" in
  "integration install"*)
    printf '%s\n' "$*" >>"$HOME/../herdr-installs"
    exit 0
    ;;
  "integration status")
    printf 'claude: not installed (%s/.claude/hooks/herdr-agent-state.ps1)\n' "$HOME"
    printf 'codex: not installed (%s/.codex/herdr-agent-state.ps1)\n' "$HOME"
    exit 0
    ;;
esac
exit 64
EOF
chmod +x "${T53}/bin/herdr"
write_hide_herdr_bootstrap "$T53"
SETUP_BASH_ENV="${T53}/hide-herdr-bootstrap.sh" run_setup "$T53"
if [ "$(component_log_block "${T53}/setup.log" herdr-integrations)" = \
    $'setup.sh: herdr-integrations\n  result: skipped (herdr expects a different hook layout)' ] \
  && [ ! -e "${T53}/herdr-installs" ]; then
  ok "a mismatched hook layout skips instead of calling the installer"
else
  ng "a mismatched hook layout reached the installer or misreported"
fi

# (35) herdr の呼び出しは CLAUDE_CONFIG_DIR / CODEX_HOME を外して行う。
# このステップは $HOME/.claude と $HOME/.codex の tracked 構成を管理するため、
# override が残ると installer と verifier が別ディレクトリを見て誤判定する。
make_temp_root T54
make_fixture "$T54"
write_herdr_hook_configs "$T54"
cat >"${T54}/bin/herdr" <<'EOF'
#!/bin/sh
case "$*" in
  "integration status")
    printf '%s %s\n' "${CLAUDE_CONFIG_DIR:-unset}" "${CODEX_HOME:-unset}" \
      >"$HOME/../herdr-env"
    printf 'claude: current (v8) (%s/.claude/hooks/herdr-agent-state.sh)\n' "$HOME"
    printf 'codex: current (v8) (%s/.codex/herdr-agent-state.sh)\n' "$HOME"
    exit 0
    ;;
esac
exit 64
EOF
chmod +x "${T54}/bin/herdr"
write_hide_herdr_bootstrap "$T54"
CLAUDE_CONFIG_DIR="${T54}/bogus-claude" CODEX_HOME="${T54}/bogus-codex" \
  SETUP_BASH_ENV="${T54}/hide-herdr-bootstrap.sh" run_setup "$T54"
if [ "$(component_log_block "${T54}/setup.log" herdr-integrations)" = \
    $'setup.sh: herdr-integrations\n  result: ok' ] \
  && [ "$(cat "${T54}/herdr-env")" = "unset unset" ]; then
  ok "herdr calls drop config-dir overrides and manage the tracked HOME"
else
  ng "herdr calls leaked config-dir overrides"
fi

# (36) 片側だけ未収束でも、install は追記ではなく上書きになる(二重登録を残さない)。
# fake の install は実機の installer と同じく「自分の絶対パス形式エントリを追記」する。
make_temp_root T55
make_fixture "$T55"
write_herdr_hook_configs "$T55"
printf '{"hooks":{"SessionStart":[]}}\n' >"${T55}/dotfiles/codex/hooks.json"
cat >"${T55}/bin/herdr" <<'EOF'
#!/bin/sh
append_hook() {
  jq --arg cmd "bash '$2' session" \
    '.hooks.SessionStart += [{"hooks":[{"type":"command","command":$cmd,"timeout":10}]}]' \
    "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}
case "$*" in
  "integration install claude")
    printf 'claude\n' >>"$HOME/../herdr-installs"
    append_hook "$HOME/.claude/settings.json" "$HOME/.claude/hooks/herdr-agent-state.sh"
    exit 0
    ;;
  "integration install codex")
    printf 'codex\n' >>"$HOME/../herdr-installs"
    append_hook "$HOME/.codex/hooks.json" "$HOME/.codex/herdr-agent-state.sh"
    exit 0
    ;;
  "integration status")
    printf 'claude: current (v8) (%s/.claude/hooks/herdr-agent-state.sh)\n' "$HOME"
    printf 'codex: current (v8) (%s/.codex/herdr-agent-state.sh)\n' "$HOME"
    exit 0
    ;;
esac
exit 64
EOF
chmod +x "${T55}/bin/herdr"
write_hide_herdr_bootstrap "$T55"
SETUP_BASH_ENV="${T55}/hide-herdr-bootstrap.sh" run_setup "$T55"
if [ "$(component_log_block "${T55}/setup.log" herdr-integrations)" = \
    $'setup.sh: herdr-integrations\n  result: ok' ] \
  && [ "$(grep -c 'herdr-agent-state.sh' "${T55}/dotfiles/claude/settings.json")" = 1 ] \
  && jq -e --arg command "bash '${T55}/home/.codex/herdr-agent-state.sh' session" \
    '[.hooks.SessionStart[]?.hooks[]? | select(.command == $command)] as $handlers
      | ($handlers | length) == 1
        and ($handlers[0].commandWindows | test("^& '\''[^'\'']*bash\\.exe'\'' -c '\''~/.codex/herdr-agent-state\\.sh session'\''$"))' \
    "${T55}/dotfiles/codex/hooks.json" >/dev/null; then
  ok "a partially converged fallback overwrites instead of appending duplicates"
else
  ng "a partially converged fallback left incomplete or duplicate hook entries"
fi

# (37) status 自体の失敗は配置不一致と区別し、failed として報告する。
make_temp_root T56
make_fixture "$T56"
write_herdr_hook_configs "$T56"
cat >"${T56}/bin/herdr" <<'EOF'
#!/bin/sh
if [ "$*" = "integration status" ]; then
  printf 'herdr: daemon unreachable\n' >&2
  exit 3
fi
exit 64
EOF
chmod +x "${T56}/bin/herdr"
write_hide_herdr_bootstrap "$T56"
SETUP_BASH_ENV="${T56}/hide-herdr-bootstrap.sh" run_setup "$T56"
if [ "$(component_log_block "${T56}/setup.log" herdr-integrations)" = \
    $'setup.sh: herdr-integrations\n  herdr integration status failed\n  result: failed (continuing)' ]; then
  ok "a status failure is reported as failed, not as a layout mismatch"
else
  ng "a status failure was misreported"
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
