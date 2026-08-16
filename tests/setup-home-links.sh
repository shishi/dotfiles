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

# setup.sh は自分の位置から DOTDIR を導くので、fixture へコピーすれば実 HOME に
# 触らずに検証できる。REMOTE_CONTAINERS=true は emacs の clone 分岐を飛ばす。
make_fixture() {
  local root="$1"
  mkdir -p "${root}/dotfiles/codex/skills" "${root}/dotfiles/nushell" \
    "${root}/dotfiles/claude" "${root}/home" "${root}/config"
  cp "$SETUP" "${root}/dotfiles/setup.sh"
  : >"${root}/dotfiles/nushell/config.nu"
  : >"${root}/dotfiles/nushell/env.nu"
  : >"${root}/dotfiles/claude/install-plugins.sh"
}

run_setup() {
  local root="$1"
  HOME="${root}/home" XDG_CONFIG_HOME="${root}/config" REMOTE_CONTAINERS=true \
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

# (1) fresh 環境で 2 本のリンクが張られる
T1="$(mktemp -d)"
trap 'rm -rf "$T1" "${T2:-}" "${T3:-}" "${T4:-}" "${T5:-}" "${T6:-}"' EXIT
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

# (2) 再実行しても壊れない (setup.sh は何度でも流せる前提)
run_setup "$T1"
if resolves_to "${T1}/home/.codex" "${T1}/dotfiles/codex" \
  && resolves_to "${T1}/home/.agents/skills" "${T1}/dotfiles/codex/skills"; then
  ok "re-running setup.sh keeps both links intact"
else
  ng "re-running setup.sh broke the Codex links"
fi

# (3) 既存の実ディレクトリを破壊しない (runtime state が入っている想定)
T2="$(mktemp -d)"
make_fixture "$T2"
mkdir -p "${T2}/home/.codex"
echo "live-secret" >"${T2}/home/.codex/auth.json"
run_setup "$T2"
if [ ! -L "${T2}/home/.codex" ] \
  && [ "$(cat "${T2}/home/.codex/auth.json" 2>/dev/null)" = "live-secret" ]; then
  ok "existing real ~/.codex is preserved, not replaced"
else
  ng "existing real ~/.codex was replaced or its contents were lost"
fi
# 「退避しろ」で終わると、退避先に auth.json が残ったまま Codex がサインアウトする。
# 戻す手順と、再実行先が worktree でないことの確認まで含まれていること。
if grep -q '\.codex exists as a real path' "${T2}/setup.log"   && grep -q '\.codex exists as a real path.*move back from there' "${T2}/setup.log"   && grep -q '\.codex exists as a real path.*temporary worktree' "${T2}/setup.log" \
  && grep -q '\.codex exists as a real path.*nests inside it' "${T2}/setup.log"; then
  ok "setup.sh reports why it skipped the Codex link, and how to adopt it without signing out"
else
  ng "setup.sh skipped the Codex link silently, or gave a remedy that strands the runtime"
fi

# (4) 別 checkout / worktree を指す既存リンクは張り替えない。張り替えると Codex は
# サインアウト状態になり、以後の runtime state はそちら側へ書かれる。
T3="$(mktemp -d)"
make_fixture "$T3"
mkdir -p "${T3}/other-checkout/codex/skills"
echo "live-secret" >"${T3}/other-checkout/codex/auth.json"
ln -sfn "${T3}/other-checkout/codex" "${T3}/home/.codex"
run_setup "$T3"
if resolves_to "${T3}/home/.codex" "${T3}/other-checkout/codex"; then
  ok "an existing link to another checkout is left alone"
else
  ng "setup.sh repointed a link that belonged to another checkout"
fi
# 報告は「どこを指しているか」と「runtime を移してから外すこと」を含む。これが無いと
# 読者はリンクを消して再実行し、Codex をサインアウトさせてしまう。
# 移送先は実行中の checkout なので、worktree から叩いたときに移すと worktree ごと
# 消える。この分岐が出る主因が worktree からの実行なので、それを先に言う。
if grep -q '\.codex links to .*other-checkout/codex; skip' "${T3}/setup.log" \
  && grep -q '\.codex links to .*; skip .*auth\.json' "${T3}/setup.log" \
  && grep -q "\.codex links to .*; skip .*${T3}/dotfiles is a temporary worktree" "${T3}/setup.log"   && grep -q '\.codex links to .*; skip .*ls-files -o -i --exclude-standard --directory' "${T3}/setup.log"; then
  ok "setup.sh names the foreign link target and how to move its runtime"
else
  ng "setup.sh repointed the foreign Codex link, or reported it without a usable remedy"
fi
# skills 側は同じ remedy を使えない。codex/skills/ は .gitignore で再包含された
# tracked サブツリーなので、runtime を移す手順を出すと資格情報を追跡対象へ入れる
# 手順になる。
ln -sfn "${T3}/other-checkout/codex/skills" "${T3}/home/.agents/skills"
run_setup "$T3"
if grep -q 'skills links to .*; skip' "${T3}/setup.log" \
  && ! grep -q 'skills links to .*auth\.json' "${T3}/setup.log"; then
  ok "the skills remedy does not tell the operator to move runtime into a tracked path"
else
  ng "the skills link was repointed, or its remedy moves runtime into codex/skills"
fi
# skills 側も remedy の締めは「外して再実行」なので、worktree から再実行させると
# ~/.agents/skills が消える予定のディレクトリを指す。同じ but を先に言う。
if grep -q "skills links to .*; skip .*${T3}/dotfiles is a temporary worktree" "${T3}/setup.log"   && grep -q 'skills links to .*; skip .*git-common-dir' "${T3}/setup.log"   && ! grep -q 'skills links to .*; skip .*move skills/\.system/' "${T3}/setup.log"; then
  ok "the skills remedy warns before telling the operator to re-run from this checkout"
else
  ng "the skills remedy tells the operator to re-run without checking this checkout is permanent"
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
T4="$(mktemp -d)"
make_fixture "$T4"
rm -rf "${T4}/dotfiles/codex"
run_setup "$T4"
if [ ! -e "${T4}/home/.codex" ] && [ ! -L "${T4}/home/.codex" ]; then
  ok "a missing link source leaves no dangling link behind"
else
  ng "setup.sh created a link even though dotfiles/codex is missing"
fi
if grep -q 'missing link source' "${T4}/setup.log"; then
  ok "setup.sh reports the missing link source"
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

T5="$(mktemp -d)"
make_fixture "$T5"
mkdir -p "${T5}/home/.claude/projects"
echo "live-history" >"${T5}/home/.claude/history.jsonl"
run_setup "$T5"
if [ ! -L "${T5}/home/.claude" ] \
  && [ "$(cat "${T5}/home/.claude/history.jsonl" 2>/dev/null)" = "live-history" ]; then
  ok "existing real ~/.claude is preserved, not replaced"
else
  ng "existing real ~/.claude was replaced or its contents were lost"
fi
# 実パスの remedy は「退避しろ」で終われない。(a) bind mount の検出はすり抜けうるので
# 確認を挟まないと mount 元へ mv を撃たせる。(b) 退避して張り直すだけでは、runtime が
# 退避先に残ったまま Claude Code がサインアウト状態で起動する。戻す手順まで要る。
if grep -q '\.claude exists as a real path' "${T5}/setup.log" \
  && grep -q '\.claude exists as a real path.*bind mount' "${T5}/setup.log" \
  && grep -q '\.claude exists as a real path.*\.credentials\.json' "${T5}/setup.log"   && grep -q '\.claude exists as a real path.*ls-files | cut -d/ -f1' "${T5}/setup.log"   && ! grep -q '\.claude exists as a real path.*ls-files -o' "${T5}/setup.log"   && grep -q '\.claude exists as a real path.*temporary worktree' "${T5}/setup.log" \
  && grep -q '\.claude exists as a real path.*nests inside it' "${T5}/setup.log"; then
  ok "setup.sh reports why it skipped the Claude link, and how to adopt it without signing out"
else
  ng "setup.sh skipped the Claude link silently, or gave a remedy that strands the runtime"
fi

# 別 checkout / worktree を指すリンクは張り替えない。実体は消えないが、Claude Code
# からは session 履歴も plugins も memory も見えなくなる。
rm -rf "${T5}/home/.claude"
mkdir -p "${T5}/other-checkout/claude/projects"
echo "live-history" >"${T5}/other-checkout/claude/history.jsonl"
ln -sfn "${T5}/other-checkout/claude" "${T5}/home/.claude"
run_setup "$T5"
if resolves_to "${T5}/home/.claude" "${T5}/other-checkout/claude"; then
  ok "an existing ~/.claude link to another checkout is left alone"
else
  ng "setup.sh repointed a ~/.claude link that belonged to another checkout"
fi
# これは rm -fr 混入専用の番人で、リンクの張り替えは検出しない (張り替えても
# unlink されるのはリンクだけで、指し先の実体は残る)。分岐の差は上の resolves_to
# が見ている。
if [ -f "${T5}/other-checkout/claude/history.jsonl" ]; then
  ok "the other checkout's Claude runtime survives (rm -fr regression guard)"
else
  ng "the other checkout's Claude runtime was destroyed"
fi
# 報告は「どこを指しているか」と「runtime を移してから外すこと」を含む。remedy が
# 無いと、読者はリンクを消して再実行し、session 履歴を参照から外してしまう。
# 資格情報を落とすとサインアウトするので、それが名指しされていることも固定する。
# 移送先は実行中の checkout なので、worktree では移してはいけないことも先に言う。
if grep -q '\.claude links to .*other-checkout/claude; skip' "${T5}/setup.log" \
  && grep -q '\.claude links to .*; skip .*sessions/' "${T5}/setup.log" \
  && grep -q '\.claude links to .*; skip .*\.credentials\.json' "${T5}/setup.log" \
  && grep -q '\.claude links to .*; skip .*temporary worktree' "${T5}/setup.log"   && grep -q "\.claude links to .*; skip .*${T5}/dotfiles is a temporary worktree" "${T5}/setup.log"   && grep -q '\.claude links to .*; skip .*git-common-dir' "${T5}/setup.log"   && grep -q '\.claude links to .*; skip .*ls-files -o -i --exclude-standard --directory' "${T5}/setup.log"; then
  ok "setup.sh names the foreign Claude link target and how to move its runtime"
else
  ng "setup.sh reported the foreign Claude link without a usable remedy"
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

# (9) ~/.agents/skills が実ディレクトリのときも、runtime (.system/) を取り残さない
# 手順を出す。同じ target の foreign remedy が「.system/ を移せ」と言っている以上、
# 実パス側だけ「退避して張り直せ」で終わると 2 つの指示が矛盾する。
T6="$(mktemp -d)"
make_fixture "$T6"
mkdir -p "${T6}/home/.agents/skills/.system"
printf 'runtime
' >"${T6}/home/.agents/skills/.system/state"
run_setup "$T6"
if [ ! -L "${T6}/home/.agents/skills" ]   && [ -f "${T6}/home/.agents/skills/.system/state" ]; then
  ok "an existing real ~/.agents/skills is preserved, not replaced"
else
  ng "an existing real ~/.agents/skills was replaced or its contents were lost"
fi
# 実パスの手順は収束しなければならない。「.system/ だけ退避して再実行」では実
# ディレクトリが残るのでリンクは永久に張られず、最後の移送で live path から
# runtime が消える。他 2 target と同じく「ディレクトリごと退避」であること。
if grep -q 'skills exists as a real path.*\.system/' "${T6}/setup.log"   && grep -q 'skills exists as a real path.*temporary worktree' "${T6}/setup.log"   && grep -q 'skills exists as a real path.*move it aside under a name that does not exist yet' "${T6}/setup.log"   && grep -q 'skills exists as a real path.*back from there' "${T6}/setup.log" \
  && grep -q 'skills exists as a real path.*nests inside it' "${T6}/setup.log"; then
  ok "the real-path skills remedy converges: aside, re-run, then move .system/ back"
else
  ng "the real-path skills remedy does not converge, or omits the worktree check"
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
