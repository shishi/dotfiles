#!/usr/bin/env bash
# PreToolUse guard for Bash: protect main/master while allowing destructive
# operations that are proven to affect only other refs.
#
# Tokenizes the command with shell-equivalent rules and inspects only arguments of
# a git invocation that stands in command position, so quoted text such as commit
# messages that merely mention "git push --force" does not false-positive.
#
# What it does NOT cover -- do not read a passing hook as "main is unreachable":
#   * Anything reached through data rather than argv: `$VAR push`, a command
#     piped into a shell, `bash script.sh`, `source`, `make`, `ssh host '...'`,
#     `powershell -EncodedCommand <base64>`.
#   * A heredoc body is scanned as if it were a command, so writing these forms
#     into a file is denied. That is the fail-closed side and is deliberate.
set -o pipefail

approval_ttl_seconds=600
approval_dir="${GIT_PUSH_GUARD_APPROVAL_DIR:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/git-push-guard-approvals-${UID:-user}}"
approval_path_out=""

approval_path_for_session() { # $1=session id -> approval_path_out
  case "$1" in
    ""|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
  [ "${#1}" -le 128 ] || return 1
  approval_path_out="$approval_dir/$1"
}

prepare_approval_dir() {
  umask 077
  if [ ! -e "$approval_dir" ]; then
    mkdir -p "$approval_dir" 2>/dev/null || return 1
  fi
  [ -d "$approval_dir" ] && [ ! -L "$approval_dir" ] && [ -O "$approval_dir" ] || return 1
  chmod 700 "$approval_dir" 2>/dev/null || return 1
}

matches_explicit_push_target() { # $1=lowercase prompt $2=target regexp
  local lower="$1" target_re="$2"
  LC_ALL=C grep -Eq \
    "^[[:space:]]*(${target_re})[[:space:]]*(に|へ)?[[:space:]]*(push|プッシュ)[[:space:]]*(して|してください|してくれ|してね)[[:space:]。！!]*$|^[[:space:]]*(${target_re})([[:space:]]+|(に|へ)[[:space:]]*)(push|プッシュ)[[:space:]。！!]*$" \
    <<< "$lower"
}

record_explicit_approval() {
  local input prompt session lower main=0 master=0 scopes tmp now
  input=$(cat)
  prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null) || exit 0
  session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
  approval_path_for_session "$session" || exit 0
  prepare_approval_dir || exit 0

  # Every user turn supersedes an unused approval from the preceding turn.
  rm -f -- "$approval_path_out" 2>/dev/null || exit 0
  case "$prompt" in *$'\n'*|*$'\r'*) exit 0 ;; esac
  lower=$(printf '%s' "$prompt" | LC_ALL=C tr '[:upper:]' '[:lower:]') || exit 0
  case "$lower" in
    *--force*|*"force push"*|*"force-push"*|*--delete*|*" delete "*|*強制*|*削除*) exit 0 ;;
    *しない*|*するな*|*禁止*|*"don't"*|*"do not"*|*never*|*"not push"*) exit 0 ;;
  esac

  if matches_explicit_push_target "$lower" 'main[[:space:]]*(と|and)[[:space:]]*master|master[[:space:]]*(と|and)[[:space:]]*main' ||
    LC_ALL=C grep -Eq '^[[:space:]]*(please[[:space:]]+)?push[[:space:]]+to[[:space:]]+main[[:space:]]+(and|&)[[:space:]]+master[[:space:].!]*$' <<< "$lower"; then
    main=1
    master=1
  else
    if matches_explicit_push_target "$lower" main ||
      LC_ALL=C grep -Eq '^[[:space:]]*(please[[:space:]]+)?push[[:space:]]+to[[:space:]]+main[[:space:].!]*$' <<< "$lower"; then
      main=1
    fi
    if matches_explicit_push_target "$lower" master ||
      LC_ALL=C grep -Eq '^[[:space:]]*(please[[:space:]]+)?push[[:space:]]+to[[:space:]]+master[[:space:].!]*$' <<< "$lower"; then
      master=1
    fi
  fi
  [ "$main" = 1 ] || [ "$master" = 1 ] || exit 0

  if [ "$main" = 1 ] && [ "$master" = 1 ]; then
    scopes=main,master
  elif [ "$main" = 1 ]; then
    scopes=main
  else
    scopes=master
  fi
  now=$(date +%s) || exit 0
  tmp=$(mktemp "$approval_dir/.approval.XXXXXX") || exit 0
  if ! printf '%s %s\n' "$now" "$scopes" > "$tmp" || ! chmod 600 "$tmp" || ! mv -f -- "$tmp" "$approval_path_out"; then
    rm -f -- "$tmp" 2>/dev/null || true
  fi
  exit 0
}

if [ "${1:-}" = "--record-approval" ]; then
  [ "$#" -eq 1 ] || exit 0
  record_explicit_approval
fi

hook_input=$(cat)
cmd=$(printf '%s' "$hook_input" | jq -r '.tool_input.command // empty')
hook_cwd=$(printf '%s' "$hook_input" | jq -r '.cwd // empty')
approval_session=$(printf '%s' "$hook_input" | jq -r '.session_id // empty')
[ -z "$cmd" ] && exit 0

# nocasematch covers the case folding that tr would otherwise need a subprocess
# for. Windows resolves GIT.EXE and git.exe alike, so every name test here is
# case-insensitive; ref and option tests become case-insensitive too, which only
# widens what is denied. It applies to `case` and `[[ ]]` -- never to `[ ]`, so
# comparisons that must fold case have to be written as `case`.
shopt -s nocasematch

# Fast path: nothing resembling git anywhere -> allow. Done with `case`
# rather than `printf | grep` so that no subprocess runs on the common path and
# `pipefail` cannot turn a grep that exits early into a silent allow. A command
# containing git but not the word push still needs tokenization because a Git
# alias can expand an arbitrary subcommand to push.
case "$cmd" in *git*) ;; *) exit 0 ;; esac

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

ask_reason=""
approval_required_main=0
approval_required_master=0
approval_required_unknown=0

request_approval() { # $1=reason $2=main|master|both|unknown
  [ -n "$ask_reason" ] || ask_reason="$1"
  case "${2:-unknown}" in
    main) approval_required_main=1 ;;
    master) approval_required_master=1 ;;
    both) approval_required_main=1; approval_required_master=1 ;;
    *) approval_required_unknown=1 ;;
  esac
}

consume_explicit_approval() {
  local line epoch scopes extra now age
  [ "$approval_required_unknown" = 0 ] || return 1
  approval_path_for_session "$approval_session" || return 1
  prepare_approval_dir || return 1
  [ -f "$approval_path_out" ] && [ ! -L "$approval_path_out" ] && [ -O "$approval_path_out" ] || return 1
  [ "$(wc -l < "$approval_path_out" | tr -d ' ')" = 1 ] || return 1
  IFS= read -r line < "$approval_path_out" || return 1
  IFS=' ' read -r epoch scopes extra <<< "$line"
  [ -n "$epoch" ] && [ -n "$scopes" ] && [ -z "$extra" ] || return 1
  case "$epoch" in ""|*[!0-9]*) return 1 ;; esac
  case "$scopes" in main|master|main,master) ;; *) return 1 ;; esac
  now=$(date +%s) || return 1
  age=$((now - epoch))
  [ "$age" -ge 0 ] && [ "$age" -le "$approval_ttl_seconds" ] || return 1
  if [ "$approval_required_main" = 1 ]; then
    case ",$scopes," in *,main,*) ;; *) return 1 ;; esac
  fi
  if [ "$approval_required_master" = 1 ]; then
    case ",$scopes," in *,master,*) ;; *) return 1 ;; esac
  fi
  rm -f -- "$approval_path_out" || return 1
  return 0
}

emit_approval_request() {
  if [ "$approval_required_unknown" = 1 ]; then
    deny "push先または更新方式を確定できないためポリシーで禁止"
  fi
  if consume_explicit_approval; then
    return 0
  fi
  jq -n --arg r "$ask_reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
}

# Tokenize with shell-equivalent rules. punctuation_chars makes shlex emit
# `;` `&&` `||` `|` `&` `(` `)` as tokens of their own even when no space
# surrounds them -- without it `cd /tmp; git push` yields the token `/tmp;` and
# the git that follows is mistaken for an argument.
# Newlines separate commands too, but shlex only treats them as whitespace, so
# they are rewritten to `;` first. Inside quotes that rewrite only alters the
# text of one token, which no decision depends on.
# python の bin 名は環境で変わる(python3 / python)。能力で解決する
py_bin=$(command -v python3 || command -v python) || py_bin=""

tokenize() { # $1=command string
  if [ -n "$py_bin" ]; then
    printf '%s' "$1" | "$py_bin" -c '
import sys, shlex
src = sys.stdin.read().replace("\n", " ; ")
try:
    lx = shlex.shlex(src, posix=True, punctuation_chars="();<>|&`")
    lx.whitespace_split = True
    for t in lx:
        print(t)
except ValueError:
    sys.exit(1)
' | tr -d '\r'
  else
    printf '%s' "$1" | xargs -n1 printf '%s\n' 2>/dev/null
  fi
}

# A git invocation is not always the bare word `git`: `git.exe`, `/usr/bin/git`
# and `C:\Program Files\Git\bin\git.exe` run the same program. Compare the
# basename, stripping both separators because a Windows path can reach us either
# way, and fold case because Windows does not distinguish it.
# Sets exe_name_out rather than echoing: a command substitution per token forks
# a subshell, and this runs once per command-position token across three
# predicates. On Git Bash that cost reaches tens of seconds for a long command
# line, past the 10s hook timeout -- a guard that times out is a guard that is
# not enforced.
exe_name_out=""
exe_name() { # $1=token -> exe_name_out = bare program name without .exe
  local base
  base="${1##*/}"
  base="${base##*\\}"
  case "$base" in
    *.[Ee][Xx][Ee]) base="${base%.???}" ;;
  esac
  exe_name_out="$base"
}

is_git_exe() { # $1=token
  exe_name "$1"
  case "$exe_name_out" in
    git) return 0 ;;
  esac
  return 1
}

# Commands that run another command given in their arguments. Treating them as
# transparent stops `env git push --force` and `timeout 30 git push --force`
# from walking past the check.
# winpty is here because Git Bash needs it to run git interactively on Windows.
is_wrapper() { # $1=token
  exe_name "$1"
  case "$exe_name_out" in
    env|command|nohup|timeout|nice|time|xargs|stdbuf|setsid|sudo|doas|winpty) return 0 ;;
  esac
  return 1
}

# Shells that take the command to run as a string argument.
shell_exe_out=""
is_shell_exe() { # $1=token -> shell_exe_out=normalized shell name
  exe_name "$1"
  case "$exe_name_out" in
    sh|bash|zsh|dash|ksh|cmd|powershell|pwsh|su)
      shell_exe_out="$exe_name_out"
      return 0
      ;;
  esac
  return 1
}

current_branch_out=""
segment_git_context=()
segment_config_unknown=0
segment_alias_config_unknown=0
segment_env_config_unknown=0
segment_env_alias_config_unknown=0
segment_cwd_unknown=0
alias_expansion_depth=0
known_git_commands_loaded=0
known_git_commands_cache=""

git_in_segment() {
  git -C "$hook_cwd" "${segment_git_context[@]}" "$@"
}

is_known_git_command() {
  if [ "$known_git_commands_loaded" = 0 ]; then
    known_git_commands_cache=$'\n'"$(git --list-cmds=main,others,nohelpers 2>/dev/null || true)"$'\n'
    known_git_commands_loaded=1
  fi
  case "$known_git_commands_cache" in
    *$'\n'"$1"$'\n'*) return 0 ;;
  esac
  return 1
}

current_branch() {
  current_branch_out=""
  [ -n "$hook_cwd" ] || return 1
  # A command that changes directory or overrides Git's repository context may
  # run the push in a different repository from hook_cwd. Do not use a branch
  # inferred from the wrong repository to allow a destructive implicit push.
  #
  # The `cd ` test below reads the whole command string, quotes included, and
  # that is deliberate even though it costs false positives (a commit message
  # mentioning cd denies a feature push). `eval 'cd elsewhere' && git push`
  # changes cwd for real -- eval runs in this shell -- but the tokenizer sees
  # one argument to eval, so segment_cwd_unknown stays 0 and this substring test
  # is what catches it. Measured: dropping `cd ` turns that command from deny
  # into allow against a mirror remote.
  #
  # It only catches that one spelling. segment_cwd_unknown tracks
  # cd|pushd|popd|chdir|set-location and `env -C`, so `eval 'pushd elsewhere'`
  # and `eval 'chdir elsewhere'` are NOT covered here and are allowed today
  # (measured). Do not read a passing hook as "cwd cannot have moved". The fix
  # is to propagate a nested cwd change back out of the eval branch rather than
  # to widen this substring list; until then, narrowing it makes things worse.
  [ "$segment_cwd_unknown" = 0 ] || return 1
  case "$cmd" in
    *"cd "*|*"GIT_DIR="*|*"GIT_WORK_TREE="*) return 1 ;;
  esac
  current_branch_out=$(git_in_segment symbolic-ref --quiet --short HEAD 2>/dev/null) || return 1
}

pattern_may_target_protected() {
  local pattern="$1"
  case "$pattern" in
    refs/heads/*) pattern="${pattern#refs/heads/}" ;;
    heads/*)
      # Git DWIM-resolves an abbreviated destination against remote refs.
      # heads/main can therefore mean refs/heads/main; the fully qualified
      # refs/heads/heads/main remains available for the literal nested branch.
      pattern="${pattern#heads/}"
      ;;
    refs/*|tags/*) return 1 ;;
  esac
  # shellcheck disable=SC2053 # RHS is intentionally a refspec glob.
  [[ main == $pattern || master == $pattern ]]
}

classify_refspec() { # $1=refspec $2=global destructive flag
  local raw="$1" destructive="$2" source dest approval_scope
  case "$raw" in
    +*) destructive=1; raw="${raw#+}" ;;
  esac

  case "$raw" in
    *:*)
      source="${raw%%:*}"
      dest="${raw#*:}"
      [ -n "$source" ] || destructive=1
      ;;
    *) dest="$raw" ;;
  esac

  if [ -z "$dest" ]; then
    if [ "$destructive" = 1 ]; then
      deny "push先を確定できない強制更新・削除はポリシーで禁止"
    fi
    request_approval "push先を確定できないため明示確認が必要"
    return 0
  fi

  case "$dest" in
    HEAD|@)
      if current_branch; then
        dest="$current_branch_out"
      elif [ "$destructive" = 1 ]; then
        deny "push先を確定できない強制更新・削除はポリシーで禁止"
      else
        request_approval "push先を確定できないため明示確認が必要"
        return 0
      fi
      ;;
  esac

  # Shell variables and command substitutions make the destination unknowable
  # to this argv-level guard. Destructive unknowns fail closed; normal updates
  # are escalated to the user.
  case "$dest" in
    *'$'*|*'`'*)
      if [ "$destructive" = 1 ]; then
        deny "push先を確定できない強制更新・削除はポリシーで禁止"
      fi
      request_approval "push先を確定できないため明示確認が必要"
      return 0
      ;;
  esac

  if pattern_may_target_protected "$dest"; then
    if [ "$destructive" = 1 ]; then
      deny "main/master の強制更新・削除はポリシーで禁止"
    fi
    case "${dest#refs/heads/}" in
      main) approval_scope=main ;;
      master) approval_scope=master ;;
      heads/main) approval_scope=main ;;
      heads/master) approval_scope=master ;;
      *) approval_scope=both ;;
    esac
    request_approval "main/master へのpushは明示確認が必要" "$approval_scope"
  fi
}

classify_implicit_push() { # $1=remote(optional) $2=global destructive flag
  local remote="$1" destructive="$2" push_default merge push_specs spec remotes candidate_remote

  if [ "$segment_config_unknown" = 1 ]; then
    if [ "$destructive" = 1 ]; then
      deny "command-local Git 設定を解決できない強制更新・削除はポリシーで禁止"
    fi
    request_approval "command-local Git 設定によりpush先が変わり得るため明示確認が必要"
    return 0
  fi

  if ! current_branch; then
    if [ "$destructive" = 1 ]; then
      deny "push先を確定できない強制更新・削除はポリシーで禁止"
    fi
    request_approval "push先を確定できないため明示確認が必要"
    return 0
  fi

  if [ -z "$remote" ]; then
    remote=$(git_in_segment config --get "branch.$current_branch_out.pushRemote" 2>/dev/null || true)
    [ -n "$remote" ] || remote=$(git_in_segment config --get remote.pushDefault 2>/dev/null || true)
    [ -n "$remote" ] || remote=$(git_in_segment config --get "branch.$current_branch_out.remote" 2>/dev/null || true)
    if [ -z "$remote" ]; then
      remotes=$(git_in_segment remote 2>/dev/null || true)
      if [ "$(printf '%s\n' "$remotes" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ]; then
        remote="$remotes"
      else
        # git pushes to origin when nothing else names a remote, so origin is
        # where the mirror and remote.*.push checks below have to look. Stopping
        # at "exactly one remote" left a fork layout (origin + upstream) with an
        # empty remote, which skips both checks: a mirror origin was allowed.
        # Compared with `[ ]`, which nocasematch does not reach: a remote named
        # ORIGIN is a different remote, and assigning "origin" for it would query
        # a config section that does not exist and read the answer as "not set".
        while IFS= read -r candidate_remote; do
          [ "$candidate_remote" = origin ] || continue
          remote=origin
          break
        done <<< "$remotes"
      fi
    fi
  fi

  if [ -n "$remote" ] && [ "$remote" != "." ]; then
    if [ "$(git_in_segment config --bool --get "remote.$remote.mirror" 2>/dev/null || true)" = true ]; then
      deny "mirror remote は main/master を強制更新・削除し得るためポリシーで禁止"
    fi
    push_specs=$(git_in_segment config --get-all "remote.$remote.push" 2>/dev/null || true)
    if [ -n "$push_specs" ]; then
      while IFS= read -r spec; do
        [ -n "$spec" ] && classify_refspec "$spec" "$destructive"
      done <<< "$push_specs"
      return 0
    fi
  fi

  push_default=$(git_in_segment config --get push.default 2>/dev/null || true)
  [ -n "$push_default" ] || push_default=simple
  case "$push_default" in
    current|simple)
      classify_refspec "$current_branch_out" "$destructive"
      ;;
    upstream)
      merge=$(git_in_segment config --get "branch.$current_branch_out.merge" 2>/dev/null || true)
      if [ -n "$merge" ]; then
        classify_refspec "$merge" "$destructive"
      elif [ "$destructive" = 1 ]; then
        deny "push先を確定できない強制更新・削除はポリシーで禁止"
      else
        request_approval "push先を確定できないため明示確認が必要"
      fi
      ;;
    matching)
      if [ "$destructive" = 1 ]; then
        deny "matching pushによるmain/masterの強制更新を除外できないためポリシーで禁止"
      fi
    request_approval "matching pushはmain/masterを含み得るため明示確認が必要" both
      ;;
    nothing) ;;
    *)
      if [ "$destructive" = 1 ]; then
        deny "push先を確定できない強制更新・削除はポリシーで禁止"
      fi
      request_approval "push先を確定できないため明示確認が必要"
      ;;
  esac
}

# Every argument of a push segment is checked exactly (not as a substring of
# quoted text).
check_segment() {
  local has_push=0 a take_next=0 skip_option_arg=0 options_done=0
  local git_option_arg=0 git_option_context=0 push_index=0 index=0 parse_index=0
  local collect_command=0
  local force=0 delete=0 mirror=0 all=0 tags=0 prune=0 remote=""
  local subcommand="" alias_value="" alias_joined="" alias_token="" autocorrect=""
  # Snapshot what the caller established for THIS segment, so the pre-scan of
  # nested command strings below cannot overwrite it.
  local entry_env_config_unknown="$segment_env_config_unknown"
  local entry_env_alias_config_unknown="$segment_env_alias_config_unknown"
  local entry_cwd_unknown="$segment_cwd_unknown"
  local positionals=() refspecs=() command_parts=() alias_tokens=() alias_args=()
  # git itself runs command strings: `submodule foreach`, `rebase --exec`,
  # `bisect run`. Quoted, the inner command is one token that never reaches the
  # push test, so it is scanned as a command line of its own.
  for a in "$@"; do
    if [ "$collect_command" = 1 ]; then
      command_parts+=("$a")
      continue
    fi
    if [ "$take_next" = 1 ]; then
      take_next=0
      case "$a" in
        -*) ;;
        # A single word cannot be a command line that reaches `git push`, so
        # re-scanning it only pays for a python3 start with no possible verdict.
        *[[:space:]]*) scan_string "$a" ;;
      esac
      continue
    fi
    case "$a" in
      foreach|run) collect_command=1 ;;
      --exec|-x) take_next=1 ;;
      # git's parse-options also accepts the joined forms `--exec=<cmd>` and
      # `-x<cmd>`.
      --exec=*|-x=*) scan_string "${a#*=}" ;;
      -x?*) scan_string "${a#-x}" ;;
    esac
  done
  if [ "${#command_parts[@]}" -eq 1 ]; then
    scan_string "${command_parts[0]}"
  elif [ "${#command_parts[@]}" -gt 1 ]; then
    scan_tokens "${command_parts[@]}"
  fi
  # The pre-scan above re-enters the scanner, and check_scanned_segment assigns
  # these three globals from its own arguments -- a nested command starts from a
  # clean context, so it writes 0 over what this segment had already
  # established. Restore them: the nested command line says nothing about
  # whether THIS segment's cwd or config could be resolved. Without this,
  # appending one nested command to a push clears the protection, e.g.
  # `git -c alias.p=push --config-env=remote.origin.mirror=FOO p --exec='git version' origin`
  # goes from deny to allow.
  segment_env_config_unknown="$entry_env_config_unknown"
  segment_env_alias_config_unknown="$entry_env_alias_config_unknown"
  segment_cwd_unknown="$entry_cwd_unknown"
  # Only Git's first non-global-option argument is a subcommand. An option value
  # such as `git log --grep push` must not be mistaken for `git push`.
  segment_git_context=()
  segment_config_unknown="$segment_env_config_unknown"
  segment_alias_config_unknown="$segment_env_alias_config_unknown"
  for a in "$@"; do
    index=$((index + 1))
    if [ "$git_option_arg" = 1 ]; then
      if [ "$git_option_context" = 2 ]; then
        case "$a" in alias.*=*) segment_alias_config_unknown=1 ;; esac
      fi
      [ "$git_option_context" != 1 ] || segment_git_context+=("$a")
      git_option_arg=0
      git_option_context=0
      continue
    fi
    case "$a" in
      -C|-c|--git-dir|--work-tree|--namespace|--super-prefix)
        segment_git_context+=("$a")
        git_option_arg=1
        git_option_context=1
        ;;
      # segment_env_config_unknown にも立てる。alias 展開と autocorrect は
      # check_segment / scan_string_with_context で再分類するが、その入口は
      # segment_config_unknown を segment_env_config_unknown から初期化し直す。
      # 継承の運び手はこの変数なので、ここに乗せないと「設定が読めない」事実が
      # 再帰の先で失われ、mirror を仕込んだ push が素通りする。
      --config-env)
        segment_config_unknown=1
        segment_env_config_unknown=1
        git_option_arg=1
        git_option_context=2
        ;;
      --config-env=*)
        segment_config_unknown=1
        segment_env_config_unknown=1
        case "${a#--config-env=}" in alias.*=*) segment_alias_config_unknown=1 ;; esac
        ;;
      --git-dir=*|--work-tree=*|--namespace=*|--super-prefix=*|-C?*|-c?*)
        segment_git_context+=("$a")
        ;;
      -*) ;;
      *) subcommand="$a"; push_index=$index; break ;;
    esac
  done
  case "$subcommand" in push) has_push=1 ;; esac

  if [ "$has_push" = 0 ] && [ -n "$subcommand" ]; then
    # Git aliases are expanded before dispatch. Resolve them with the same
    # per-invocation -C/-c context, then feed the expanded argv back through
    # this classifier. A bounded depth matches Git's own loop rejection.
    is_known_git_command "$subcommand" && return 0
    [ "$segment_alias_config_unknown" = 0 ] || deny "Git alias の設定値を解決できないためポリシーで禁止"
    alias_args=("${@:push_index + 1}")
    alias_value=$(git_in_segment config --get "alias.$subcommand" 2>/dev/null || true)
    if [ -z "$alias_value" ]; then
      autocorrect=$(git_in_segment config --get help.autocorrect 2>/dev/null || true)
      case "$autocorrect" in ""|0|false|no|never) [ "$segment_config_unknown" = 0 ] && return 0 ;; esac
      # An unknown subcommand can be corrected to push. Classify its argv as a
      # push so protected effects stay guarded while feature-only effects keep
      # their normal policy.
      check_segment "${segment_git_context[@]}" push "${alias_args[@]}"
      return 0
    fi
    [ "$alias_expansion_depth" -lt 10 ] || deny "Git alias の展開が深すぎるためポリシーで禁止"
    alias_expansion_depth=$((alias_expansion_depth + 1))
    case "$alias_value" in
      !*)
        alias_joined="${alias_value#!}"
        for alias_token in "${alias_args[@]}"; do
          printf -v alias_joined '%s %q' "$alias_joined" "$alias_token"
        done
        scan_string_with_context "$segment_env_config_unknown" "$segment_env_alias_config_unknown" "$segment_cwd_unknown" "$alias_joined"
        ;;
      *)
        while IFS= read -r alias_token; do alias_tokens+=("$alias_token"); done < <(tokenize "$alias_value")
        [ "${#alias_tokens[@]}" -gt 0 ] || deny "Git alias を解析できないためポリシーで禁止"
        check_segment "${segment_git_context[@]}" "${alias_tokens[@]}" "${alias_args[@]}"
        ;;
    esac
    alias_expansion_depth=$((alias_expansion_depth - 1))
    return 0
  fi
  [ "$has_push" = 1 ] || return 0

  for a in "$@"; do
    parse_index=$((parse_index + 1))
    if [ "$parse_index" -le "$push_index" ]; then
      continue
    fi
    if [ "$skip_option_arg" = 1 ]; then
      skip_option_arg=0
      continue
    fi
    if [ "$skip_option_arg" = repo ]; then
      remote="$a"
      skip_option_arg=0
      continue
    fi
    if [ "$options_done" = 0 ]; then
      case "$a" in
        --) options_done=1; continue ;;
        --force-if-includes) continue ;;
        --force*|--f|--fo|--for|--forc) force=1; continue ;;
        --delete|--del*|--de) delete=1; continue ;;
        --mirror|--mir*|--mi) mirror=1; continue ;;
        --all|--al|--branches) all=1; continue ;;
        --tags|--tag*) tags=1; continue ;;
        --prune|--pru*|--pr) prune=1; continue ;;
        --recurse-submodules=*|--no-recurse-submodules=*) continue ;;
        --no-recu*) continue ;;
        --recu*) skip_option_arg=1; continue ;;
        --no-rep*) continue ;;
        --rep*=*) remote="${a#*=}"; continue ;;
        --rep*) skip_option_arg=repo; continue ;;
        --no-push*|--no-rece*|--no-ex*) continue ;;
        --push*=*|--rece*=*|--ex*=*) continue ;;
        -o|--push*|--rece*|--ex*) skip_option_arg=1; continue ;;
        -o?*) continue ;;
        -[A-Za-z]*)
          case "$a" in *f*) force=1 ;; esac
          case "$a" in *d*) delete=1 ;; esac
          continue
          ;;
        -*) continue ;;
      esac
    fi
    positionals+=("$a")
  done

  # --mirror force-updates and deletes refs across namespaces. It can never be
  # proven to exclude the protected branches from argv alone.
  [ "$mirror" = 0 ] || deny "--mirror は main/master を強制更新・削除し得るためポリシーで禁止"

  if [ "${#positionals[@]}" -gt 1 ]; then
    remote="${positionals[0]}"
    refspecs=("${positionals[@]:1}")
  elif [ "${#positionals[@]}" -eq 1 ]; then
    remote="${positionals[0]}"
  fi

  if [ "${#refspecs[@]}" -gt 0 ]; then
    local destructive="$force"
    [ "$delete" = 0 ] || destructive=1
    [ "$prune" = 0 ] || destructive=1
    local tag_argument=0
    for a in "${refspecs[@]}"; do
      if [ "$tag_argument" = 1 ]; then
        tag_argument=0
        continue
      fi
      if [ "$a" = tag ]; then
        tag_argument=1
        continue
      fi
      classify_refspec "$a" "$destructive"
    done
    return 0
  fi

  # --all necessarily includes main/master when those local branches exist.
  # Without executing Git's full transport negotiation, normal --all needs user
  # confirmation and destructive --all must fail closed.
  if [ "$all" = 1 ]; then
    if [ "$force" = 1 ] || [ "$delete" = 1 ] || [ "$prune" = 1 ]; then
      deny "--all による main/master の強制更新・削除を除外できないためポリシーで禁止"
    fi
    request_approval "--all は main/master を含み得るため明示確認が必要" both
    return 0
  fi

  # --tags updates only refs/tags/*; a current branch named main/master is not
  # an implicit branch destination in this form.
  [ "$tags" = 0 ] || return 0

  # An unscoped prune can delete a protected remote branch missing locally.
  [ "$prune" = 0 ] || deny "--prune による main/master の削除を除外できないためポリシーで禁止"

  # With no explicit refspec, Git derives the destination from the current
  # branch and push configuration. A protected current branch is sufficient to
  # enforce policy; an unresolved destructive destination fails closed.
  local destructive="$force"
  [ "$delete" = 0 ] || destructive=1
  classify_implicit_push "$remote" "$destructive"
  return 0
}

scan_string() { # $1=command string; returns 1 when it cannot be tokenized
  local toklist t
  local toks=()
  toklist=$(tokenize "$1") || return 1
  while IFS= read -r t; do toks+=("$t"); done <<< "$toklist"
  scan_tokens "${toks[@]}"
  return 0
}

scan_inherited_env_config_unknown=0
scan_inherited_env_alias_unknown=0
scan_inherited_cwd_unknown=0

scan_string_with_context() { # $1=config unknown $2=alias unknown $3=cwd unknown $4=command
  local previous_config="$scan_inherited_env_config_unknown"
  local previous_alias="$scan_inherited_env_alias_unknown"
  local previous_cwd="$scan_inherited_cwd_unknown"
  scan_inherited_env_config_unknown="$1"
  scan_inherited_env_alias_unknown="$2"
  scan_inherited_cwd_unknown="$3"
  scan_string "$4"
  local rc=$?
  scan_inherited_env_config_unknown="$previous_config"
  scan_inherited_env_alias_unknown="$previous_alias"
  scan_inherited_cwd_unknown="$previous_cwd"
  return "$rc"
}

scan_shell_command_tokens() { # $1=config unknown $2=alias unknown $3=cwd unknown, rest=tokens
  local config_unknown="$1" alias_unknown="$2" cwd_unknown="$3" joined="" token
  shift 3
  for token in "$@"; do
    joined="${joined}${joined:+ }${token}"
  done
  [ -z "$joined" ] || scan_string_with_context "$config_unknown" "$alias_unknown" "$cwd_unknown" "$joined"
}

check_scanned_segment() { # $1=env config unknown $2=env alias unknown $3=cwd unknown, rest=args
  segment_env_config_unknown="$1"
  segment_env_alias_config_unknown="$2"
  segment_cwd_unknown="$3"
  shift 3
  check_segment "$@"
}

# Walk tokens tracking command position. Only a git token in command position
# opens a segment: `echo git push --force` mentions git in argument position and
# must stay allowed, while `cd /tmp; git push origin master` executes it after a
# separator and must not.
scan_tokens() {
  local at_cmd=1 in_git=0 shell_pending=0 shell_mode="" wrapper_pending=0 wrapper_mode="" redir_pending=0 eval_pending=0 t
  local pending_env_config_unknown="$scan_inherited_env_config_unknown"
  local pending_env_alias_unknown="$scan_inherited_env_alias_unknown"
  local cwd_may_have_changed="$scan_inherited_cwd_unknown"
  local git_env_config_unknown=0 git_env_alias_unknown=0
  local shell_env_config_unknown=0 shell_env_alias_unknown=0
  local shell_cwd_unknown=0
  local seg=() shell_command_tokens=()
  for t in "$@"; do
    # A redirection does not end the command: `git push > /dev/null --force` is
    # still one invocation. Skip the operator and its target without closing the
    # segment. Handled before the separator test because `>` is punctuation too.
    if [ "$redir_pending" = 1 ]; then
      redir_pending=0
      # Only a filename can be the target. A punctuation-only token here means
      # the `>` was a quoted argument, so the real separator must not be eaten;
      # fall through to the separator test below.
      case "$t" in
        *[!\(\)\;\<\>\|\&\`]*|"") continue ;;
      esac
    fi
    case "$t" in
      # A brace opens or closes a command group wherever it appears, so it
      # restores command position even mid-command. Without this,
      # `function f { git push --force ...; }` lets the function name consume
      # command position and the git inside is read as an argument.
      "{"|"}")
        [ "$in_git" = 0 ] || check_scanned_segment "$git_env_config_unknown" "$git_env_alias_unknown" "$cwd_may_have_changed" "${seg[@]}"
        [ "$shell_pending" != 3 ] || scan_shell_command_tokens "$shell_env_config_unknown" "$shell_env_alias_unknown" "$shell_cwd_unknown" "${shell_command_tokens[@]}"
        in_git=0
        seg=()
        shell_command_tokens=()
        at_cmd=1
        shell_pending=0
        eval_pending=0
        wrapper_pending=0
        pending_env_config_unknown="$scan_inherited_env_config_unknown"
        pending_env_alias_unknown="$scan_inherited_env_alias_unknown"
        continue
        ;;
    esac
    case "$t" in
      *[!\(\)\;\<\>\|\&\`]*) ;;
      "") ;;
      *)
        # A token made only of punctuation. shlex merges adjacent punctuation
        # into one token (`);` `)&&` `;(`), so listing exact separators would
        # miss every combined form and leave the next git in argument position.
        case "$t" in
          # Process substitution `<(` / `>(` is a command position, not a
          # redirection: a command follows it. Test for a paren first so the
          # combined token falls through to the separator handling below.
          *[\(\)]*) ;;
          *[\<\>]*)
            # A herestring feeds a shell its command line: `bash <<<'git push
            # --force'` runs it. Treating it as a plain redirection would throw
            # that line away as if it were a filename. Only `<<<` counts: a
            # plain redirect before -c writes to a file and must not be taken
            # for the command string.
            case "$t" in
              "<<<")
                if [ "$shell_pending" != 0 ]; then
                  shell_pending=2
                  continue
                fi
                ;;
            esac
            redir_pending=1
            continue
            ;;
        esac
        [ "$in_git" = 0 ] || check_scanned_segment "$git_env_config_unknown" "$git_env_alias_unknown" "$cwd_may_have_changed" "${seg[@]}"
        [ "$shell_pending" != 3 ] || scan_shell_command_tokens "$shell_env_config_unknown" "$shell_env_alias_unknown" "$shell_cwd_unknown" "${shell_command_tokens[@]}"
        in_git=0
        seg=()
        shell_command_tokens=()
        at_cmd=1
        shell_pending=0
        eval_pending=0
        wrapper_pending=0
        pending_env_config_unknown="$scan_inherited_env_config_unknown"
        pending_env_alias_unknown="$scan_inherited_env_alias_unknown"
        continue
        ;;
    esac
    # After a wrapper, the command it runs is not necessarily the next token
    # (`timeout 30 git push`). Keep looking until this segment's git shows up;
    # tokens that are not git are the wrapper's own arguments.
    if [ "$wrapper_pending" = 1 ]; then
      case "$t" in
        HOME=*|XDG_CONFIG_HOME=*|GIT_CONFIG_GLOBAL=*|GIT_CONFIG_SYSTEM=*|GIT_CONFIG_NOSYSTEM=*|GIT_DIR=*|GIT_COMMON_DIR=*|GIT_WORK_TREE=*)
          pending_env_config_unknown=1
          pending_env_alias_unknown=1
          continue
          ;;
        GIT_CONFIG_COUNT=*|GIT_CONFIG_KEY_*=*|GIT_CONFIG_VALUE_*=*)
          pending_env_config_unknown=1
          case "$t" in GIT_CONFIG_KEY_*=alias.*) pending_env_alias_unknown=1 ;; esac
          continue
          ;;
        GIT_CONFIG_PARAMETERS=*)
          pending_env_config_unknown=1
          pending_env_alias_unknown=1
          continue
          ;;
      esac
      if [ "$wrapper_mode" = env ]; then
        case "$t" in
          -C|--chdir|-C?*|--chdir=*) cwd_may_have_changed=1; continue ;;
        esac
      fi
      exe_name "$t"
      case "$exe_name_out" in
        cd|pushd|popd|chdir|set-location)
          cwd_may_have_changed=1
          wrapper_pending=0
          at_cmd=0
          continue
          ;;
      esac
      if is_git_exe "$t"; then
        wrapper_pending=0
        at_cmd=0
        in_git=1
        git_env_config_unknown="$pending_env_config_unknown"
        git_env_alias_unknown="$pending_env_alias_unknown"
        seg=()
      elif is_shell_exe "$t"; then
        wrapper_pending=0
        shell_mode="$shell_exe_out"
        shell_env_config_unknown="$pending_env_config_unknown"
        shell_env_alias_unknown="$pending_env_alias_unknown"
        shell_cwd_unknown="$cwd_may_have_changed"
        shell_pending=1
        at_cmd=0
      elif is_wrapper "$t"; then
        wrapper_mode="$exe_name_out"
      fi
      continue
    fi
    # `sh -c <string>`: the string is a command line of its own, so scan it.
    # Waiting for the -c switch first, rather than taking the next non-option,
    # is what keeps `su someuser -c '<cmd>'` from consuming the user name as if
    # it were the command. cmd.exe spells it /c and PowerShell -Command.
    if [ "$shell_pending" = 1 ]; then
      case "$t" in
        # Short options bundle and -c must sit last in the cluster because it
        # takes the next argument, so `bash -lc` and `sh -ec` are the switch
        # too. MSYS rewrites a lone /c into a Windows path, which is why the
        # idiomatic Git Bash form is `cmd //c`.
        -EncodedCommand) shell_pending=2 ;;
        -[Cc]ommand|/[CcKk]|//[CcKk])
          case "$shell_mode" in
            cmd|powershell|pwsh) shell_pending=3 ;;
            *) shell_pending=2 ;;
          esac
          ;;
        -c|-[A-Za-z]*c) shell_pending=2 ;;
      esac
      continue
    fi
    if [ "$shell_pending" = 3 ]; then
      shell_command_tokens+=("$t")
      continue
    fi
    if [ "$shell_pending" = 2 ]; then
      # Options may still follow the -c switch (`bash -c -x '<cmd>'`), so keep
      # waiting until a non-option arrives rather than scanning the first token.
      case "$t" in
        -*) continue ;;
      esac
      shell_pending=0
      scan_string_with_context "$shell_env_config_unknown" "$shell_env_alias_unknown" "$shell_cwd_unknown" "$t"
      continue
    fi
    # eval joins its arguments back into one command line, so it is neither a
    # wrapper (the command may arrive quoted as a single token) nor a shell
    # taking exactly one string (it may arrive as separate words).
    if [ "$eval_pending" = 1 ]; then
      eval_pending=0
      case "$t" in
        *[[:space:]]*)
          scan_string_with_context "$pending_env_config_unknown" "$pending_env_alias_unknown" "$cwd_may_have_changed" "$t"
          continue
          ;;
      esac
      at_cmd=1
    fi
    if [ "$at_cmd" = 1 ]; then
      # A leading VAR=value assignment does not consume command position:
      # `GIT_DIR=/tmp/x git push --force` still executes git.
      case "$t" in
        [A-Za-z_]*=*)
          case "$t" in
            HOME=*|XDG_CONFIG_HOME=*|GIT_CONFIG_GLOBAL=*|GIT_CONFIG_SYSTEM=*|GIT_CONFIG_NOSYSTEM=*|GIT_DIR=*|GIT_COMMON_DIR=*|GIT_WORK_TREE=*)
              pending_env_config_unknown=1
              pending_env_alias_unknown=1
              ;;
            GIT_CONFIG_COUNT=*|GIT_CONFIG_KEY_*=*|GIT_CONFIG_VALUE_*=*)
              pending_env_config_unknown=1
              case "$t" in GIT_CONFIG_KEY_*=alias.*) pending_env_alias_unknown=1 ;; esac
              ;;
            GIT_CONFIG_PARAMETERS=*)
              pending_env_config_unknown=1
              pending_env_alias_unknown=1
              ;;
          esac
          continue
          ;;
      esac
      case "$t" in
        eval) eval_pending=1; at_cmd=0; continue ;;
      esac
      # Shell keywords stand where a command stands but are not the command:
      # after `do` or `then` the real command follows. Consuming command
      # position here would leave `for r in ...; do git push --force` with git
      # in argument position.
      case "$t" in
        do|done|then|fi|else|elif|if|while|until|for|select|"case"|"esac"|in|function|"{"|"}"|"!"|time|coproc|exec|builtin)
          continue
          ;;
      esac
      exe_name "$t"
      case "$exe_name_out" in
        cd|pushd|popd|chdir|set-location)
          cwd_may_have_changed=1
          at_cmd=0
          continue
          ;;
      esac
      if is_wrapper "$t"; then
        wrapper_pending=1
        wrapper_mode="$exe_name_out"
        continue
      fi
      if is_shell_exe "$t"; then
        shell_mode="$shell_exe_out"
        shell_env_config_unknown="$pending_env_config_unknown"
        shell_env_alias_unknown="$pending_env_alias_unknown"
        shell_cwd_unknown="$cwd_may_have_changed"
        shell_pending=1
        at_cmd=0
        continue
      fi
      at_cmd=0
      [ "$in_git" = 0 ] || check_scanned_segment "$git_env_config_unknown" "$git_env_alias_unknown" "$cwd_may_have_changed" "${seg[@]}"
      seg=()
      if is_git_exe "$t"; then
        in_git=1
        git_env_config_unknown="$pending_env_config_unknown"
        git_env_alias_unknown="$pending_env_alias_unknown"
      else
        in_git=0
      fi
      continue
    fi
    [ "$in_git" = 1 ] && seg+=("$t")
  done
  [ "$in_git" = 0 ] || check_scanned_segment "$git_env_config_unknown" "$git_env_alias_unknown" "$cwd_may_have_changed" "${seg[@]}"
  [ "$shell_pending" != 3 ] || scan_shell_command_tokens "$shell_env_config_unknown" "$shell_env_alias_unknown" "$shell_cwd_unknown" "${shell_command_tokens[@]}"
  return 0
}

if ! scan_string "$cmd"; then
  # Could not be parsed at all. This path exists to fail closed, so it errs
  # toward denying: it covers every argument the exact check rejects.
  # Fed by herestring, not a pipe. Through a pipe, grep -q exits at the first
  # match and the still-writing printf takes EPIPE, which pipefail turns into a
  # non-zero pipeline -- the deny would be skipped exactly when the input is
  # long and dangerous. This is the last line of defence, so it must not depend
  # on how a subprocess exits.
  if grep -Eqi -- '--force|--delete|--mirror|--all|--prune|(^|[[:space:]])-[A-Za-z]*[fd]|(^|[[:space:]:+])(refs/heads/)?(main|master)([[:space:]]|$)|[[:space:]]:[^[:space:]]' <<< "$cmd"; then
    deny "git push コマンドを解析できず、危険な引数らしき文字列を含むためポリシーでブロック"
  fi
  exit 0
fi

[ -z "$ask_reason" ] || emit_approval_request
exit 0
