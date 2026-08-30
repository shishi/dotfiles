#!/usr/bin/env bash
# setup.sh の emacs clone 分岐 (link_config_dir ... ~/.emacs.d を張る箇所) の検証。
#
# clone は認証欠如・ネットワーク断・実行中断で失敗しうる。失敗したときに
# ~/.emacs.d へ symlink を張ってしまうと、それ自体が「取得済み」の印になって
# 次回の再試行を止める。さらに link_config_dir は対象が実ディレクトリなら
# rm -fr するため、既存の設定を消したうえで壊れたリンクだけが残る。
#
# GIT_SSH_COMMAND=false により ssh を即座に失敗させ、
# ネットワークの状態に依存せず clone を落とす。
set -u

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

make_fixture() {
  local root="$1"
  mkdir -p "${root}/dotfiles/codex/skills" "${root}/dotfiles/nushell" \
    "${root}/dotfiles/claude" "${root}/dotfiles/wezterm" "${root}/dotfiles/fish" \
    "${root}/dotfiles/nvim" "${root}/dotfiles/helix" "${root}/home" "${root}/config"
  cp "$SETUP" "${root}/dotfiles/setup.sh"
  : >"${root}/dotfiles/nushell/config.nu"
  : >"${root}/dotfiles/nushell/env.nu"
  : >"${root}/dotfiles/claude/install-plugins.sh"
}

# REMOTE_CONTAINERS=false で emacs 分岐へ入る。GIT_SSH_COMMAND=false は ssh の
# 代わりに false を起動させるので、clone は必ず失敗する。
run_setup() {
  local root="$1"
  HOME="${root}/home" XDG_CONFIG_HOME="${root}/config" REMOTE_CONTAINERS=false \
    GIT_SSH_COMMAND=false \
    bash "${root}/dotfiles/setup.sh" >>"${root}/setup.log" 2>&1
}

T1="$(mktemp -d)"
trap 'rm -rf "$T1" "${T2:-}" "${T3:-}" "${T4:-}" "${T5:-}" "${T6:-}" "${T7:-}"' EXIT

# 1. clone が失敗したら ~/.emacs.d を作らない。
#    壊れたリンクを残すと、それ自体が「取得済み」の印として次回を止める。
make_fixture "$T1"
run_setup "$T1"
if [ ! -e "${T1}/home/.emacs.d" ] && [ ! -L "${T1}/home/.emacs.d" ]; then
  ok "a failed emacs clone leaves no ~/.emacs.d behind"
else
  ng "~/.emacs.d exists after a failed clone (dangling link blocks the retry)"
fi

# 2. 失敗は次回に持ち越さない。2 回実行すれば clone は 2 回試みられる。
#    git 自身が出す fatal を数える (setup.sh の文言に依存しないため)。
T2="$(mktemp -d)"
make_fixture "$T2"
run_setup "$T2"
run_setup "$T2"
attempts="$(grep -c 'fatal' "${T2}/setup.log" || true)"
if [ "$attempts" -ge 2 ]; then
  ok "a failed emacs clone is retried on the next run (${attempts} attempts)"
else
  ng "the emacs clone was attempted ${attempts} time(s) across two runs; the failure latched"
fi

# 3. clone が失敗したときに、既存の ~/.emacs.d を巻き添えにしない。
#    link_config_dir は実ディレクトリを rm -fr するので、clone の成否に関係なく
#    呼ぶと利用者の設定が消える。
T3="$(mktemp -d)"
make_fixture "$T3"
mkdir -p "${T3}/home/.emacs.d"
echo "user config" >"${T3}/home/.emacs.d/init.el"
run_setup "$T3"
if [ -f "${T3}/home/.emacs.d/init.el" ]; then
  ok "an existing ~/.emacs.d survives a failed clone"
else
  ng "an existing ~/.emacs.d was destroyed by a failed clone"
fi

# 4. 新規マシンの known_hosts は空で、素の git clone は host key 確認の対話で止まる。
#    ssh を記録用の stub に差し替えて、accept-new が実際に git へ渡ることを見る。
#    GIT_SSH_COMMAND はここでは渡さない (setup.sh の既定値が使われる経路を測る)。
T4="$(mktemp -d)"
make_fixture "$T4"
mkdir -p "${T4}/bin"
cat >"${T4}/bin/ssh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${SSH_STUB_LOG}"
exit 1
STUB
chmod +x "${T4}/bin/ssh"
HOME="${T4}/home" XDG_CONFIG_HOME="${T4}/config" REMOTE_CONTAINERS=false \
  GIT_SSH_COMMAND= SSH_STUB_LOG="${T4}/ssh-args.log" PATH="${T4}/bin:$PATH" \
  bash "${T4}/dotfiles/setup.sh" >>"${T4}/setup.log" 2>&1
if [ -s "${T4}/ssh-args.log" ] \
  && grep -q 'StrictHostKeyChecking=accept-new' "${T4}/ssh-args.log"; then
  ok "the emacs clone reaches ssh with accept-new, so an empty known_hosts cannot block it"
else
  ng "ssh was invoked without accept-new (or not at all); a fresh machine stops at the host key prompt"
fi

# 5. clone 先に repo でない残骸があるとき (SIGKILL や電源断で残る)、それを
#    「取得済み」と誤認しない。誤認すると壊れた中身へリンクし、利用者の
#    実ディレクトリを rm -fr したうえで再試行も止まる。
T5="$(mktemp -d)"
make_fixture "$T5"
mkdir -p "${T5}/emacs"
echo "leftover" >"${T5}/emacs/partial"
mkdir -p "${T5}/home/.emacs.d"
echo "user config" >"${T5}/home/.emacs.d/init.el"
run_setup "$T5"
run_setup "$T5"
leftover_attempts="$(grep -c 'fatal' "${T5}/setup.log" || true)"
if [ -f "${T5}/home/.emacs.d/init.el" ]; then
  ok "a non-repo leftover at the clone target does not destroy an existing ~/.emacs.d"
else
  ng "a non-repo leftover at the clone target destroyed an existing ~/.emacs.d"
fi
if [ "$leftover_attempts" -ge 2 ]; then
  ok "a non-repo leftover is not mistaken for a finished clone (${leftover_attempts} attempts)"
else
  ng "a non-repo leftover was treated as a finished clone (${leftover_attempts} attempt(s))"
fi

# 6. 旧版が残した dangling な ~/.emacs.d から回復する。回復できないと、既に
#    壊れているマシンはこの修正を入れても直らない。
T6="$(mktemp -d)"
make_fixture "$T6"
ln -sfn "${T6}/emacs" "${T6}/home/.emacs.d"
run_setup "$T6"
if grep -q 'fatal' "${T6}/setup.log"; then
  ok "a pre-existing dangling ~/.emacs.d does not stop the clone from being retried"
else
  ng "a pre-existing dangling ~/.emacs.d permanently suppresses the clone"
fi

# 7. .git はあるが中身が揃っていない残骸を「取得済み」と誤認しない。通常の
#    認証失敗・ネットワーク断では git 自身が後始末するが、SIGKILL や電源断では
#    .git だけが残る。誤認すると clone を試みず警告も出さないまま、利用者の
#    実 ~/.emacs.d を rm -fr して中身の無いディレクトリへリンクする。
T7="$(mktemp -d)"
make_fixture "$T7"
mkdir -p "${T7}/emacs/.git"
mkdir -p "${T7}/home/.emacs.d"
echo "user config" >"${T7}/home/.emacs.d/init.el"
run_setup "$T7"
run_setup "$T7"
half_attempts="$(grep -c 'fatal' "${T7}/setup.log" || true)"
if [ -f "${T7}/home/.emacs.d/init.el" ]; then
  ok "an incomplete checkout at the clone target does not destroy an existing ~/.emacs.d"
else
  ng "an incomplete checkout at the clone target destroyed an existing ~/.emacs.d"
fi
if [ "$half_attempts" -ge 2 ]; then
  ok "an incomplete checkout is not mistaken for a finished clone (${half_attempts} attempts)"
else
  ng "an incomplete checkout was treated as a finished clone (${half_attempts} attempt(s))"
fi

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
