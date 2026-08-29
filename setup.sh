#!/bin/bash

# Git Bash/MSYS では素の ln -s が symlink ではなく「コピー」を作るため、
# native symlink を強制する (要: Windows 開発者モード or 管理者実行)。
# export しておけば以降の ln 呼び出しすべてに効く。mac/Linux では何もしない。
case "$(uname -s)" in
  MINGW* | MSYS*) export MSYS=winsymlinks:nativestrict ;;
esac

if [ -d /.jbdevcontainer ]; then
  XDG_CONFIG_HOME=/.jbdevcontainer/config
elif [ -z $XDG_CONFIG_HOME ]; then
  XDG_CONFIG_HOME=$HOME/.config
  mkdir -p ~/.config
fi

DOTDIR=$(realpath $(dirname "$0"))

# リンクはすべて ln -sfn で張る。-n (--no-dereference) が無いと、既にディレクトリを
# 指す symlink が張り替えではなく「その中へ」張られる (ln -sf が L を辿って
# L/basename(T) を作る)。ファイルへのリンクでは -n は無害なので例外を作らない。
#
# エディタ設定は repo が正本で runtime を持たないため、実ディレクトリは中身ごと
# 捨てて置き換える。auth.json や session を抱える agent home (link_agent_home) とは
# 方針が違うのはここ。
link_config_dir() {
  local source_path="$1" target_path="$2"

  if [ ! -L "$target_path" ] && [ -d "$target_path" ]; then
    rm -fr "$target_path"
  fi
  ln -sfn "$source_path" "$target_path"
}

# 新規マシンの known_hosts は空なので、素の git clone は host key 確認の対話で
# 止まる。そこで止まらないよう新しいホスト鍵を受理する。環境側で設定済みなら
# そちらを尊重する。尊重するのは環境変数の値で、git config の core.sshCommand は
# 環境変数の方が優先されるため上書きする。export なので後続の gh と
# install-plugins.sh の git にも効く。
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o StrictHostKeyChecking=accept-new}"

if [ "$REMOTE_CONTAINERS" != true ]; then
  link_config_dir "${DOTDIR}/wezterm" "${XDG_CONFIG_HOME}/wezterm"

  emacs_dir="$(dirname "${DOTDIR}")/emacs"
  # 取得済みかどうかは HEAD が解決できるかで見る。~/.emacs.d が symlink かどうかで
  # 見ると、旧版が clone 失敗時に残した dangling link を「取得済み」と誤認する。
  # .git の有無で見ると、SIGKILL や電源断で .git だけ残った状態を誤認する
  # (通常の認証失敗やネットワーク断では git 自身が後始末するので残らない)。
  # HEAD の解決なら linked worktree (.git がファイル) も正しく拾える。
  emacs_ready() { git -C "${emacs_dir}" rev-parse --verify HEAD >/dev/null 2>&1; }
  if ! emacs_ready; then
    git -C "$(dirname "${DOTDIR}")" clone git@github.com:shishi/emacs.git \
      || echo "setup.sh: could not clone emacs into ${emacs_dir} (ssh key missing? interrupted?); rerun setup.sh, or remove a leftover first: rm -rf ${emacs_dir}"
  fi
  # 取得できたときだけ張る。失敗したまま張ると壊れたリンクが残り、既存の実
  # ディレクトリは link_config_dir の rm -fr で消える。
  if emacs_ready; then
    link_config_dir "${emacs_dir}" ~/.emacs.d
  fi
fi

link_config_dir "${DOTDIR}/fish" "${XDG_CONFIG_HOME}/fish"
link_config_dir "${DOTDIR}/nvim" "${XDG_CONFIG_HOME}/nvim"
link_config_dir "${DOTDIR}/helix" "${XDG_CONFIG_HOME}/helix"

# agent のホーム (~/.claude ~/.codex ~/.agents/{skills,bin,hooks}) を張る。実行後は必ずこの
# checkout を指している状態にする。既に何かが在れば .back へ退避してから張る。
# 消さないのは、ignore された runtime (auth.json / sessions/ / history.jsonl /
# plugins/) がそこに同居しているため。退避先から必要な分を戻すのは手作業。
#
# 比較は解決した実パスで行う。文字列比較だと cd の失敗 (空文字) を「別の場所を
# 指している」と取り違える。
link_agent_home() {
  local source_path="$1" target_path="$2"
  local source_real target_real backup n

  source_real="$(cd "$source_path" 2>/dev/null && pwd -P)"
  if [ -z "$source_real" ]; then
    echo "setup.sh: missing ${source_path}; skip"
    return 0
  fi
  if [ -L "$target_path" ]; then
    target_real="$(cd "$target_path" 2>/dev/null && pwd -P)"
    # 既に正しい。張り替えないので、symlink を作れない環境で再実行しても失わない。
    [ "$target_real" = "$source_real" ] && return 0
    # dangling は退避するものが無い。リンク先を失うので捨てた値だけ残す。
    if [ ! -e "$target_path" ]; then
      echo "setup.sh: ${target_path} was a dangling link to $(readlink "$target_path")"
      rm -f "$target_path"
    fi
  fi
  if [ -e "$target_path" ] || [ -L "$target_path" ]; then
    # 退避先は衝突させない。mv は既存ディレクトリへ向けると中へ入れ子になる。
    backup="${target_path}.back"
    n=1
    while [ -e "$backup" ] || [ -L "$backup" ]; do
      backup="${target_path}.back.${n}"
      n=$((n + 1))
    done
    if mv "$target_path" "$backup"; then
      # symlink なら mv はリンク自身を動かすので、指し先の実体には触らない。
      echo "setup.sh: moved ${target_path} to ${backup} (move its runtime back from there)"
    else
      echo "setup.sh: could not move ${target_path} aside; skip"
      return 0
    fi
  fi
  ln -sfn "$source_path" "$target_path" \
    || echo "setup.sh: could not link ${target_path} (Windows: enable Developer Mode or run elevated)"
}

# bind mount (devcontainer 等) は実パスとして現れるので、実パス扱いの前に見る。
# 越しに同じ実体が見えているため退避は不要で、退避すると mount 元へ作用する。
# mountpoint で検出できない実装 (Docker Desktop の virtiofs/9p 等) は /proc/mounts で
# 拾う。mount 元が ${DOTDIR}/claude と同じかは照合していない。
if [ ! -L ~/.claude ] \
  && { mountpoint -q ~/.claude 2>/dev/null \
    || grep -qE "[[:space:]]$HOME/\.claude[[:space:]]" /proc/mounts 2>/dev/null; }; then
  echo "setup.sh: ~/.claude is a mount point; skip (check the source with findmnt -no SOURCE ~/.claude)"
else
  link_agent_home "${DOTDIR}/claude" "$HOME/.claude"
fi

# gitconfig は agent-memory 処理より前に張る。ヘルパーが git config の
# ghq.root を参照するため、後だと fresh 環境の初回実行だけ既定 root へ
# clone される二段階挙動になってしまう。
if [ $(uname) = Darwin ]; then
  ln -sfn ${DOTDIR}/.gitconfig.mac ~/.gitconfig
  ln -sfn ${DOTDIR}/Brewfile ~/Brewfile
elif [ $(uname) = Linux ]; then
  ln -sfn ${DOTDIR}/.gitconfig.linux ~/.gitconfig
  #    link_config_dir ${DOTDIR}/terminator ${XDG_CONFIG_HOME}/terminator
  #    ln -sfn ${DOTDIR}/.xprofile ~/.xprofile
  #    ln -sfn ${DOTDIR}/.xbindkeysrc ~/.xbindkeysrc
  #    ln -sfn ${DOTDIR}/.imwheelrc ~/.imwheelrc
  #    ln -sfn ${DOTDIR}/imwheel.desktop ${XDG_CONFIG_HOME}/autostart/imwheel.desktop
  #    ln -sfn ${DOTDIR}/fonts.conf ${XDG_CONFIG_HOME}/fontconfig/fonts.conf
  #    fc-cache -fv
elif [[ $(uname -s) == MINGW* ]]; then
  # uname はビルド番号付き (例: MINGW64_NT-10.0-26200) なのでパターンで判定する
  ln -sfn ${DOTDIR}/.gitconfig.win ~/.gitconfig
fi

# realpath/readlink -f は実装によって dangling link にも非空を返すため、存在確認を
# 先に行う。directory と regular file のどちらを指す valid link も物理解決できる。
resolve_existing_path() {
  local path="$1"

  [ -e "$path" ] || return 1
  realpath "$path" 2>/dev/null
}

run_with_indented_output() {
  local -a pipeline_status

  "$@" 2>&1 | sed 's/^/  /' 2>/dev/null
  pipeline_status=("${PIPESTATUS[@]}")
  if [ "${pipeline_status[1]}" -ne 0 ]; then
    echo "  output formatting failed (exit ${pipeline_status[1]})"
  fi
  if [ "${pipeline_status[0]}" -ne 0 ]; then
    return "${pipeline_status[0]}"
  fi
  return "${pipeline_status[1]}"
}

has_herdr_command_hook() {
  local config="$1" command="$2"

  jq -e --arg command "$command" \
    'any(.hooks.SessionStart[]?.hooks[]?; .type == "command" and .command == $command)' \
    "$config" >/dev/null 2>&1
}

codex_herdr_windows_command() {
  printf '%s\n' \
    "& 'C:/Users/shishi/scoop/apps/git/current/bin/bash.exe' -c '~/.codex/herdr-agent-state.sh session'"
}

has_codex_herdr_command_hook() {
  local config="$1" installed_command windows_command

  installed_command="bash '$HOME/.codex/herdr-agent-state.sh' session"
  windows_command="$(codex_herdr_windows_command)"
  jq -e \
    --arg tracked_command 'bash ~/.codex/herdr-agent-state.sh session' \
    --arg installed_command "$installed_command" \
    --arg windows_command "$windows_command" \
    'any(.hooks.SessionStart[]?.hooks[]?;
      .type == "command"
        and (.command == $tracked_command or .command == $installed_command)
        and .commandWindows == $windows_command)' \
    "$config" >/dev/null 2>&1
}

ensure_codex_herdr_windows_command() {
  local config="$1" installed_command tmp windows_command

  [ -f "$config" ] || return 1
  has_codex_herdr_command_hook "$config" && return 0
  installed_command="bash '$HOME/.codex/herdr-agent-state.sh' session"
  windows_command="$(codex_herdr_windows_command)"
  jq -e \
    --arg tracked_command 'bash ~/.codex/herdr-agent-state.sh session' \
    --arg installed_command "$installed_command" \
    'any(.hooks.SessionStart[]?.hooks[]?;
      .type == "command"
        and (.command == $tracked_command or .command == $installed_command))' \
    "$config" >/dev/null 2>&1 || return 1
  tmp="$(mktemp "${config}.XXXXXX")" || return 1
  if jq \
    --arg tracked_command 'bash ~/.codex/herdr-agent-state.sh session' \
    --arg installed_command "$installed_command" \
    --arg windows_command "$windows_command" \
    '.hooks.SessionStart |= map(
      .hooks |= map(
        if .type == "command"
          and (.command == $tracked_command or .command == $installed_command)
        then .commandWindows = $windows_command
        else .
        end
      )
    )' "$config" >"$tmp" \
    && mv "$tmp" "$config"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# herdr integration の後条件。hook エントリは tracked 設定が使うチルダ形式と、
# herdr の installer が書く絶対パス(単引用符)形式のどちらでも満たす。
# Codex hook は Windows 用 command も必須とする。
# herdr は CLAUDE_CONFIG_DIR / CODEX_HOME を尊重するが、このステップは
# $HOME/.claude と $HOME/.codex の tracked 構成を管理するため、herdr の呼び出し
# からは override を外し、verifier と同じディレクトリを見せる。
herdr_integrations_verified() {
  local herdr_integration_status

  command -v herdr >/dev/null 2>&1 || return 1
  herdr_integration_status="$(env -u CLAUDE_CONFIG_DIR -u CODEX_HOME \
    herdr integration status 2>/dev/null)" || return 1
  printf '%s\n' "$herdr_integration_status" | grep -Eq '^claude: current( |$)' \
    && printf '%s\n' "$herdr_integration_status" | grep -Eq '^codex: current( |$)' \
    && { has_herdr_command_hook "$HOME/.claude/settings.json" \
        'bash ~/.claude/hooks/herdr-agent-state.sh session' \
      || has_herdr_command_hook "$HOME/.claude/settings.json" \
        "bash '$HOME/.claude/hooks/herdr-agent-state.sh' session"; } \
    && has_codex_herdr_command_hook "$HOME/.codex/hooks.json"
}

# herdr が管理しようとする hook の配置(status が括弧内に示すパス)が tracked
# 構成(bash + .sh)と一致するときだけ installer を許す。Windows 版 herdr は
# PowerShell hook (.ps1) を書き、HERDR_INTEGRATION_ID を含む既存の .sh hook を
# 削除するため、配置不一致のまま install すると tracked hook を破壊する。
# 引数は取得済みの `herdr integration status` の出力(取得失敗は呼び出し側が
# 別状態として扱う)。
herdr_hook_layout_matches() {
  printf '%s\n' "$1" \
    | grep -Fq "($HOME/.claude/hooks/herdr-agent-state.sh)" \
    && printf '%s\n' "$1" \
      | grep -Fq "($HOME/.codex/herdr-agent-state.sh)"
}

# install は追記で動き、既存のチルダ形式エントリと併存すると SessionStart hook が
# 二重実行になる。install の前に herdr hook エントリを取り除き、installer の書く
# 形式だけが残る上書きにする。
remove_herdr_hook_entries() {
  local config="$1" tmp

  [ -f "$config" ] || return 0
  jq -e 'any(.hooks.SessionStart[]?.hooks[]?; .command | contains("herdr-agent-state"))' \
    "$config" >/dev/null 2>&1 || return 0
  tmp="$(mktemp "${config}.XXXXXX")" || return 1
  if jq '.hooks.SessionStart |= map(select(any(.hooks[]?; .command | contains("herdr-agent-state")) | not))' \
    "$config" >"$tmp"; then
    mv "$tmp" "$config"
  else
    rm -f "$tmp"
    return 1
  fi
}

normalize_agent_memory_remote() {
  local remote="$1"

  remote="${remote%/}"
  remote="${remote%.git}"
  case "$remote" in
    git@github.com:*) printf 'github.com/%s\n' "${remote#git@github.com:}" ;;
    https://github.com/*) printf 'github.com/%s\n' "${remote#https://github.com/}" ;;
    ssh://git@github.com/*) printf 'github.com/%s\n' "${remote#ssh://git@github.com/}" ;;
    *) return 1 ;;
  esac
}

validate_agent_memory_repository() {
  local candidate="$1" candidate_real repository_root repository_real origin normalized_origin commit

  candidate_real="$(resolve_existing_path "$candidate")" || {
    echo "setup.sh: could not resolve agent-memory repository: $candidate"
    return 1
  }
  repository_root="$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "setup.sh: agent-memory path is not a Git worktree: $candidate"
    return 1
  }
  repository_real="$(resolve_existing_path "$repository_root")" || {
    echo "setup.sh: could not resolve agent-memory worktree root: $repository_root"
    return 1
  }
  # Git for Windows は C:/...、MSYS realpath は /tmp/... のように同じ inode を
  # 別表記で返す。文字列でなく filesystem identity で root 一致を検証する。
  [ "$candidate_real" -ef "$repository_real" ] || {
    echo "setup.sh: agent-memory path is not the worktree root: $candidate"
    return 1
  }

  origin="$(git -C "$candidate" remote get-url origin 2>/dev/null)" || {
    echo "setup.sh: agent-memory repository has no origin: $candidate"
    return 1
  }
  normalized_origin="$(normalize_agent_memory_remote "$origin")" || {
    echo "setup.sh: unsupported agent-memory origin: $origin"
    return 1
  }
  [ "$normalized_origin" = github.com/shishi/agent-memory ] || {
    echo "setup.sh: unexpected agent-memory origin: $origin"
    return 1
  }
  commit="$(git -C "$candidate" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || {
    echo "setup.sh: agent-memory repository has no committed HEAD: $candidate"
    return 1
  }
  if [ "$(git -C "$candidate" cat-file -t "$commit:MEMORY.md" 2>/dev/null)" != blob ] ||
    [ "$(git -C "$candidate" cat-file -t "$commit:CONVENTIONS.md" 2>/dev/null)" != blob ]; then
    echo "setup.sh: agent-memory HEAD lacks MEMORY.md or CONVENTIONS.md: $candidate"
    return 1
  fi
}

move_memory_path_no_follow() {
  local source_path="$1" target_path="$2"

  case "$(uname -s)" in
    Darwin | FreeBSD | OpenBSD | NetBSD) mv -h -n "$source_path" "$target_path" ;;
    *) mv -T -n "$source_path" "$target_path" ;;
  esac
}

memory_symlink_matches() {
  local link_path="$1" expected_literal="$2" expected_real="$3" actual_real

  [ -n "$expected_real" ] || return 1
  [ -L "$link_path" ] || return 1
  [ "$(readlink "$link_path")" = "$expected_literal" ] || return 1
  actual_real="$(resolve_existing_path "$link_path")" || return 1
  [ "$actual_real" = "$expected_real" ] || return 1
}

dangling_memory_symlink_matches() {
  local link_path="$1" expected_literal="$2"

  [ -L "$link_path" ] || return 1
  [ "$(readlink "$link_path")" = "$expected_literal" ] || return 1
  [ ! -e "$link_path" ] || return 1
}

remove_owned_memory_symlink() {
  local link_path="$1" expected_literal="$2" expected_real="$3"

  memory_symlink_matches "$link_path" "$expected_literal" "$expected_real" ||
    return 1
  rm -f "$link_path"
}

remove_owned_dangling_memory_symlink() {
  local link_path="$1" expected_literal="$2"

  dangling_memory_symlink_matches "$link_path" "$expected_literal" ||
    return 1
  rm -f "$link_path"
}

release_memory_lock() {
  [ "$memory_lock_owned" = true ] || return 0
  [ -f "$memory_lock_owner_file" ] ||
    return 1
  [ "$(cat "$memory_lock_owner_file" 2>/dev/null)" = "$memory_lock_token" ] ||
    return 1
  rm -f "$memory_lock_owner_file" ||
    return 1
  memory_lock_owned=false
  if ! rmdir "$memory_lock"; then
    echo "setup.sh: could not release memory setup lock: $memory_lock"
    return 1
  fi
}

handle_memory_signal() {
  local status="$1"

  if [ -z "$memory_pending_signal_status" ]; then
    memory_pending_signal_status="$status"
  fi
  if [ "$memory_transaction_critical" = true ]; then
    return 0
  fi
  release_memory_lock || :
  trap - EXIT HUP INT TERM
  exit "$memory_pending_signal_status"
}

finish_memory_transaction() {
  local status

  release_memory_lock || :
  memory_transaction_critical=false
  if [ -n "$memory_pending_signal_status" ]; then
    status="$memory_pending_signal_status"
    trap - EXIT HUP INT TERM
    exit "$status"
  fi
}

# agent-memory (個人永続記憶, private repo) を Claude/Codex 双方から参照させる。
# 配置先は agents/bin/resolve-memory-dir.sh が解決する (ghq.root 対応。解決のみで実体は
# 移動しない)。共有配置は
# docs/superpowers/specs/2026-08-18-shared-agent-memory-hardening-design.md を参照。
# resolver の挙動契約は agents/bin/resolve-memory-dir.sh と
# tests/agent-memory-ghq.sh が正。
# symlink は dotfiles の .gitignore により追跡されない。
AGENT_MEMORY_DIR="$(bash "${DOTDIR}/agents/bin/resolve-memory-dir.sh")"
resolve_status=$?
# setup.sh には set -e がないため、ヘルパーの失敗や壊れた出力 (空・複数行・
# 相対パス) をここで検証しないと後続の clone/symlink が変な場所に走る。
case "$AGENT_MEMORY_DIR" in
  "") resolve_status=1 ;;
  *"
"*) resolve_status=1 ;;
  /*) ;;
  *) resolve_status=1 ;;
esac
memory_lock="$HOME/.agent-memory-setup.lock"
memory_lock_owner_file="$memory_lock/owner"
memory_lock_token="setup-$$"
memory_lock_owned=false
memory_transaction_critical=false
memory_pending_signal_status=""
if [ "$resolve_status" -eq 0 ]; then
  if mkdir "$memory_lock" 2>/dev/null; then
    if printf '%s\n' "$memory_lock_token" >"$memory_lock_owner_file"; then
      memory_lock_owned=true
      trap 'release_memory_lock || :' EXIT
      trap 'handle_memory_signal 129' HUP
      trap 'handle_memory_signal 130' INT
      trap 'handle_memory_signal 143' TERM
    else
      rmdir "$memory_lock" 2>/dev/null || :
      echo "setup.sh: could not record memory setup lock owner; skip memory setup"
      resolve_status=2
    fi
  else
    echo "setup.sh: memory setup lock is busy ($memory_lock); skip memory setup"
    resolve_status=2
  fi
fi
if [ "$resolve_status" -eq 2 ]; then
  :
elif [ "$resolve_status" -ne 0 ]; then
  echo "setup.sh: could not resolve agent-memory location; skip memory setup"
else
  if [ ! -d "${AGENT_MEMORY_DIR}" ]; then
    # ghq root 配下の中間ディレクトリ (github.com/shishi) は fresh 環境に
    # 存在せず、git clone は親を作らない。
    mkdir -p "$(dirname "${AGENT_MEMORY_DIR}")"
    # private repo なので認証必須。ssh 鍵 → gh の順に試し、両方だめなら
    # メッセージだけ出して続行する (setup.sh 全体を止めない)。
    git clone git@github.com:shishi/agent-memory.git "${AGENT_MEMORY_DIR}" 2>/dev/null \
      || gh repo clone shishi/agent-memory "${AGENT_MEMORY_DIR}" 2>/dev/null \
      || echo "setup.sh: could not clone agent-memory (ssh key / gh auth missing?); clone manually: git clone git@github.com:shishi/agent-memory.git ${AGENT_MEMORY_DIR}"
  fi
  if [ -d "${AGENT_MEMORY_DIR}" ] &&
    validate_agent_memory_repository "${AGENT_MEMORY_DIR}"; then
    memory_blocked=false
    memory_real="$(resolve_existing_path "${AGENT_MEMORY_DIR}")"
    if [ -z "$memory_real" ]; then
      echo "setup.sh: could not resolve canonical agent-memory repository; memory targets unchanged"
      memory_blocked=true
    fi
    memory_targets=("${DOTDIR}/claude/memory" "${DOTDIR}/codex/memory")
    memory_states=(missing missing)
    memory_literals=("" "")
    memory_temps=("" "")
    memory_backups=("" "")
    memory_prepared=(false false)
    memory_changed=(false false)
    memory_detached=(false false)
    memory_backup_removed=(false false)

    # 片方を変更してからもう片方の衝突に気付くと split brain になるため、2 target
    # とも先に調べる。dangling は実体を持たないので、報告したうえで修復可能とする。
    for i in 0 1; do
      memory_target="${memory_targets[$i]}"
      if [ -L "$memory_target" ]; then
        if [ ! -e "$memory_target" ]; then
          memory_states[$i]=dangling
          memory_literals[$i]="$(readlink "$memory_target")"
          echo "setup.sh: ${memory_target} was a dangling link to $(readlink "$memory_target")"
        else
          target_real="$(resolve_existing_path "$memory_target")"
          if [ -z "$target_real" ]; then
            echo "setup.sh: could not resolve ${memory_target}; memory targets unchanged"
            memory_blocked=true
          elif [ "$target_real" != "$memory_real" ]; then
            echo "setup.sh: ${memory_target} resolves elsewhere (${target_real}); memory targets unchanged"
            memory_blocked=true
          else
            memory_states[$i]=canonical
          fi
        fi
      elif [ -e "$memory_target" ]; then
        echo "setup.sh: ${memory_target} exists as a real path; memory targets unchanged"
        memory_blocked=true
      fi
    done

    if [ "$memory_blocked" = true ]; then
      echo "setup.sh: skip both memory links (manual setup required)"
    else
      # validation/re-resolution/preflightまではsignalで即時中止できる。tempを作り始めた
      # 後だけはsplit stateを避けるため、transaction終了まで最初のsignalを遅延する。
      memory_transaction_critical=true
      # 両方の symlink を本番 target と別名で先に作る。1 本でも作成・検証に失敗
      # したら、本番 target には触れず、自分が作成した temp だけを片付ける。
      memory_prepare_ok=true
      memory_failure=""
      for i in 0 1; do
        [ "${memory_states[$i]}" = canonical ] && continue
        memory_target="${memory_targets[$i]}"
        memory_temps[$i]="${memory_target}.setup-$$.new"
        memory_backups[$i]="${memory_target}.setup-$$.back"
        memory_temp="${memory_temps[$i]}"
        memory_backup="${memory_backups[$i]}"

        if [ -e "$memory_temp" ] || [ -L "$memory_temp" ] \
          || [ -e "$memory_backup" ] || [ -L "$memory_backup" ]; then
          memory_prepare_ok=false
          memory_failure="temporary path already exists for ${memory_target}"
          break
        fi
        if ! ln -s "${AGENT_MEMORY_DIR}" "$memory_temp"; then
          memory_prepare_ok=false
          memory_failure="could not prepare ${memory_target}"
          break
        fi
        memory_prepared[$i]=true
        target_real="$(resolve_existing_path "$memory_temp")"
        if [ ! -L "$memory_temp" ] || [ "$target_real" != "$memory_real" ]; then
          memory_prepare_ok=false
          memory_failure="prepared path is not a canonical symlink for ${memory_target}"
          break
        fi
      done

      # preparation 中に別プロセスが target を変更していないことも、switch 前に
      # 2 本まとめて再確認する。
      if [ "$memory_prepare_ok" = true ]; then
        for i in 0 1; do
          memory_target="${memory_targets[$i]}"
          case "${memory_states[$i]}" in
            canonical)
              target_real="$(resolve_existing_path "$memory_target")"
              if [ ! -L "$memory_target" ] || [ "$target_real" != "$memory_real" ]; then
                memory_prepare_ok=false
              fi
              ;;
            dangling)
              if [ ! -L "$memory_target" ] || [ -e "$memory_target" ] \
                || [ "$(readlink "$memory_target")" != "${memory_literals[$i]}" ]; then
                memory_prepare_ok=false
              fi
              ;;
            missing)
              if [ -e "$memory_target" ] || [ -L "$memory_target" ]; then
                memory_prepare_ok=false
              fi
              ;;
          esac
          if [ "$memory_prepare_ok" != true ]; then
            memory_failure="memory target changed during preparation: ${memory_target}"
            break
          fi
        done
      fi

      if [ "$memory_prepare_ok" != true ]; then
        for i in 0 1; do
          memory_temp="${memory_temps[$i]}"
          if [ "${memory_prepared[$i]}" = true ] \
            && { [ -e "$memory_temp" ] || [ -L "$memory_temp" ]; }; then
            remove_owned_memory_symlink "$memory_temp" "${AGENT_MEMORY_DIR}" "$memory_real" ||
              echo "setup.sh: could not clean owned temporary memory link ${memory_temp}"
          fi
        done
        echo "setup.sh: could not prepare both memory links; targets unchanged (${memory_failure})"
      else
        # 全 temp の検証後だけ本番 target を切り替える。dangling link は literal を
        # 保ったまま backup へ移し、途中失敗時に同じ link 自体を戻せるようにする。
        memory_switch_ok=true
        for i in 0 1; do
          [ "${memory_states[$i]}" = canonical ] && continue
          memory_target="${memory_targets[$i]}"
          memory_temp="${memory_temps[$i]}"
          memory_backup="${memory_backups[$i]}"

          if [ "${memory_states[$i]}" = dangling ]; then
            if move_memory_path_no_follow "$memory_target" "$memory_backup" &&
              [ ! -e "$memory_target" ] && [ ! -L "$memory_target" ] &&
              dangling_memory_symlink_matches "$memory_backup" "${memory_literals[$i]}"; then
              memory_detached[$i]=true
            else
              memory_switch_ok=false
              memory_failure="could not preserve dangling link ${memory_target}"
              break
            fi
          fi
          if move_memory_path_no_follow "$memory_temp" "$memory_target" &&
            [ ! -e "$memory_temp" ] && [ ! -L "$memory_temp" ] &&
            memory_symlink_matches "$memory_target" "${AGENT_MEMORY_DIR}" "$memory_real"; then
            memory_prepared[$i]=false
            memory_changed[$i]=true
          else
            memory_switch_ok=false
            memory_failure="could not switch ${memory_target}"
            break
          fi
        done

        # switch 後も両方が本物の symlink かつ同じ物理解決先でなければ失敗扱い。
        if [ "$memory_switch_ok" = true ]; then
          for i in 0 1; do
            memory_target="${memory_targets[$i]}"
            if ! memory_symlink_matches "$memory_target" \
              "${AGENT_MEMORY_DIR}" "$memory_real"; then
              memory_switch_ok=false
              memory_failure="memory link postcondition failed for ${memory_target}"
              break
            fi
          done
        fi

        # 成功時だけ旧 dangling backup を捨てる。失敗した removal も rollback の
        # 対象にし、既に消した backup は保存した literal から best-effort で戻す。
        if [ "$memory_switch_ok" = true ]; then
          for i in 0 1; do
            memory_backup="${memory_backups[$i]}"
            [ -n "$memory_backup" ] || continue
            if [ -L "$memory_backup" ]; then
              if ! remove_owned_dangling_memory_symlink "$memory_backup" \
                "${memory_literals[$i]}"; then
                memory_switch_ok=false
                memory_failure="could not clean memory backup ${memory_backup}"
                break
              fi
              memory_backup_removed[$i]=true
            elif [ -e "$memory_backup" ]; then
              memory_switch_ok=false
              memory_failure="memory backup changed unexpectedly: ${memory_backup}"
              break
            fi
          done
        fi

        if [ "$memory_switch_ok" != true ]; then
          memory_rollback_ok=true
          for i in 1 0; do
            memory_target="${memory_targets[$i]}"
            memory_backup="${memory_backups[$i]}"

            if [ "${memory_changed[$i]}" = true ]; then
              if [ -L "$memory_target" ]; then
                remove_owned_memory_symlink "$memory_target" \
                  "${AGENT_MEMORY_DIR}" "$memory_real" ||
                  memory_rollback_ok=false
              elif [ -e "$memory_target" ]; then
                # 予期しない実パスは削除しない。
                memory_rollback_ok=false
              fi
            fi
            if [ "${memory_states[$i]}" = dangling ] \
              && [ "${memory_detached[$i]}" = true ] \
              && [ ! -e "$memory_target" ] && [ ! -L "$memory_target" ]; then
              if dangling_memory_symlink_matches "$memory_backup" \
                "${memory_literals[$i]}"; then
                if ! move_memory_path_no_follow "$memory_backup" "$memory_target" \
                  || { [ -e "$memory_backup" ] || [ -L "$memory_backup" ]; } \
                  || ! dangling_memory_symlink_matches "$memory_target" \
                    "${memory_literals[$i]}"; then
                  memory_rollback_ok=false
                fi
              elif [ "${memory_backup_removed[$i]}" = true ]; then
                if ! ln -s "${memory_literals[$i]}" "$memory_target" \
                  || ! dangling_memory_symlink_matches "$memory_target" \
                    "${memory_literals[$i]}"; then
                  memory_rollback_ok=false
                fi
              else
                memory_rollback_ok=false
              fi
            fi
          done

          # rollback成功を宣言する前に、2 targetともtransaction前の状態へ戻ったことを
          # literal/realpath込みで確認する。mv -nのno-op成功もここで誤魔化せない。
          for i in 0 1; do
            memory_target="${memory_targets[$i]}"
            case "${memory_states[$i]}" in
              canonical)
                target_real="$(resolve_existing_path "$memory_target")"
                [ -L "$memory_target" ] && [ "$target_real" = "$memory_real" ] ||
                  memory_rollback_ok=false
                ;;
              dangling)
                dangling_memory_symlink_matches "$memory_target" \
                  "${memory_literals[$i]}" ||
                  memory_rollback_ok=false
                ;;
              missing)
                if [ -e "$memory_target" ] || [ -L "$memory_target" ]; then
                  memory_rollback_ok=false
                fi
                ;;
            esac
          done

          for i in 0 1; do
            memory_temp="${memory_temps[$i]}"
            if [ "${memory_prepared[$i]}" = true ] \
              && { [ -e "$memory_temp" ] || [ -L "$memory_temp" ]; }; then
              remove_owned_memory_symlink "$memory_temp" \
                "${AGENT_MEMORY_DIR}" "$memory_real" ||
                memory_rollback_ok=false
            fi
          done
          for i in 0 1; do
            memory_backup="${memory_backups[$i]}"
            if [ -n "$memory_backup" ] \
              && { [ -e "$memory_backup" ] || [ -L "$memory_backup" ]; }; then
              echo "setup.sh: rollback left memory backup at ${memory_backup}"
              memory_rollback_ok=false
            fi
          done
          if [ "$memory_rollback_ok" = true ]; then
            echo "setup.sh: memory link switch failed; rolled back both targets (${memory_failure})"
          else
            echo "setup.sh: memory link switch failed; rollback incomplete (${memory_failure})"
          fi
        fi
      fi
    fi
  else
    echo "setup.sh: ${AGENT_MEMORY_DIR} is not the canonical agent-memory repository; skip memory symlink"
  fi
fi
finish_memory_transaction

# Codex CLI は CODEX_HOME (既定 ~/.codex) をディレクトリ単位で読む。~/.agents は
# personal skills と、Claude/Codex が共有する runtime を指す。
link_agent_home "${DOTDIR}/codex" "$HOME/.codex"
if mkdir -p ~/.agents; then
  link_agent_home "${DOTDIR}/codex/skills" "$HOME/.agents/skills"
  link_agent_home "${DOTDIR}/agents/bin" "$HOME/.agents/bin"
  link_agent_home "${DOTDIR}/agents/hooks" "$HOME/.agents/hooks"
else
  echo "setup.sh: could not create ~/.agents; skip shared agent links"
fi

# nushell はディレクトリ単位で差し替えない。Nushell 自身が同じ場所へ history や
# plugin registry を書くため、ディレクトリは実体のまま残し、中の 2 ファイルだけを張る。
# symlink になっていたら実ディレクトリへ戻す。repo のディレクトリを直接指していると、
# Nushell の生成物が worktree の中へ落ちる。
# 宛先はファイル名まで書く。ディレクトリを宛先にすると、そこが symlink だったときに
# ディレクトリ自身が最後の 1 ファイルへのリンクに化ける。
if [ -L ${XDG_CONFIG_HOME}/nushell ]; then
  rm ${XDG_CONFIG_HOME}/nushell
fi
mkdir -p ${XDG_CONFIG_HOME}/nushell
ln -sfn ${DOTDIR}/nushell/config.nu ${XDG_CONFIG_HOME}/nushell/config.nu
ln -sfn ${DOTDIR}/nushell/env.nu ${XDG_CONFIG_HOME}/nushell/env.nu

# 単一ファイルは HOME 直下に同名で張る。ディレクトリと違い repo が唯一の実体で、
# runtime を持たないので実ファイルが在っても置き換えてよい。
for f in .ideavimrc .vimrc .gvimrc .gemrc .rspec .pryrc .npmrc; do
  ln -sfn "${DOTDIR}/${f}" "$HOME/${f}"
done

# 名前が変わるのはこれだけ。gitconfig の core.excludesFile が ~/.gitignore を見る。
ln -sfn ${DOTDIR}/.gitignore.global ~/.gitignore

# .bashrc / .zsh 系 / .vim は追跡しているが張らない。

# settings.json の enabledPlugins に従って Claude Code plugin を install する。
echo "setup.sh: claude-plugins"
if command -v claude >/dev/null 2>&1; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "  result: skipped (jq not found)"
  elif [ ! -f "$HOME/.claude/settings.json" ]; then
    echo "  result: skipped (settings.json not found)"
  elif run_with_indented_output env INSTALL_PLUGINS_SUMMARY=0 \
    bash "${DOTDIR}/claude/install-plugins.sh"; then
    echo "  result: ok"
  else
    echo "  result: failed (continuing)"
  fi
else
  echo "  result: skipped (claude not found)"
fi

# herdr integration(~/.claude / ~/.codex の hook)の版ズレをここで収束させる。
# nix-config の herdr-bootstrap が PATH に居ればそれを使い(plugin 照合も内包する)、
# 無ければ herdr 自身の公開 CLI で同じ収束を行う(private な wrapper を必須にしない)。
# どちらも無い環境(nix 未導入)では次の home-manager switch が同じことをする。
echo "setup.sh: herdr-integrations"
if command -v herdr-bootstrap >/dev/null 2>&1; then
  herdr_integrations_ok=0
  if run_with_indented_output env INSTALL_PLUGINS_QUIET=1 \
    INSTALL_PLUGINS_SUMMARY=0 herdr-bootstrap \
    && ensure_codex_herdr_windows_command "$HOME/.codex/hooks.json" \
    && herdr_integrations_verified; then
    herdr_integrations_ok=1
  fi
  if [ "$herdr_integrations_ok" -eq 1 ]; then
    echo "  result: ok"
  else
    echo "  result: failed (continuing)"
  fi
elif ! command -v herdr >/dev/null 2>&1; then
  echo "  result: skipped (herdr not found)"
elif ! command -v jq >/dev/null 2>&1; then
  # 後条件の検証(has_herdr_command_hook)が jq を要する。検証できない環境では
  # 書き込まない。
  echo "  result: skipped (jq not found)"
elif ! herdr_integration_status_output="$(env -u CLAUDE_CONFIG_DIR -u CODEX_HOME \
  herdr integration status 2>/dev/null)"; then
  echo "  herdr integration status failed"
  echo "  result: failed (continuing)"
elif ! herdr_hook_layout_matches "$herdr_integration_status_output"; then
  echo "  result: skipped (herdr expects a different hook layout)"
else
  herdr_integrations_ok=0
  # 収束済みなら書き込まない。healthy な機で installer を走らせると tracked
  # 設定に毎回 diff を作るため。
  if herdr_integrations_verified; then
    herdr_integrations_ok=1
  elif remove_herdr_hook_entries "$HOME/.claude/settings.json" \
    && remove_herdr_hook_entries "$HOME/.codex/hooks.json" \
    && run_with_indented_output env -u CLAUDE_CONFIG_DIR -u CODEX_HOME \
      herdr integration install claude \
    && run_with_indented_output env -u CLAUDE_CONFIG_DIR -u CODEX_HOME \
      herdr integration install codex \
    && ensure_codex_herdr_windows_command "$HOME/.codex/hooks.json" \
    && herdr_integrations_verified; then
    herdr_integrations_ok=1
  fi
  if [ "$herdr_integrations_ok" -eq 1 ]; then
    echo "  result: ok"
  else
    echo "  result: failed (continuing)"
  fi
fi

# Hunk は実行中の版と対応する skill を同梱している。固定コピーを追跡せず、
# setup のたびに現在の bundled skill へ張り直して Hunk 更新へ追随する。
echo "setup.sh: hunk-review-skills"
if command -v hunk >/dev/null 2>&1; then
  hunk_review_skills_ok=0
  hunk_review_skill="$(hunk skill path hunk-review 2>/dev/null)" || hunk_review_skill=
  if [ -n "$hunk_review_skill" ] && [ -f "$hunk_review_skill" ]; then
    hunk_review_skills_ok=1
    hunk_review_skill_real="$(resolve_existing_path "$hunk_review_skill")" \
      || hunk_review_skills_ok=0
    for skill_home in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
      hunk_skill_dir="${skill_home}/hunk-review"
      if [ -L "$hunk_skill_dir" ] && ! rm "$hunk_skill_dir"; then
        echo "  could not replace ${hunk_skill_dir} symlink; skip Hunk skill"
        hunk_review_skills_ok=0
        continue
      fi
      if mkdir -p "$hunk_skill_dir"; then
        if ! ln -sfn "$hunk_review_skill" "$hunk_skill_dir/SKILL.md"; then
          echo "  could not link Hunk skill into ${skill_home} (continuing)"
          hunk_review_skills_ok=0
        fi
      else
        echo "  could not create ${hunk_skill_dir}; skip Hunk skill"
        hunk_review_skills_ok=0
      fi
    done
    for skill_home in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
      hunk_skill_file="${skill_home}/hunk-review/SKILL.md"
      hunk_skill_file_real="$(resolve_existing_path "$hunk_skill_file")" \
        || hunk_skill_file_real=
      if [ ! -L "$hunk_skill_file" ] \
        || [ "$hunk_skill_file_real" != "$hunk_review_skill_real" ]; then
        hunk_review_skills_ok=0
      fi
    done
  else
    echo "  hunk-review skill path is unavailable (continuing)"
  fi
  if [ "$hunk_review_skills_ok" -eq 1 ]; then
    echo "  result: ok"
  else
    echo "  result: failed (continuing)"
  fi
else
  echo "  result: skipped (hunk not found)"
fi

# Codex の plugin は Claude Code と違いアカウント側に保存され、サインインすれば
# マシンをまたいで復元される。ここで収束させる必要はない。

echo "please reload shell"
