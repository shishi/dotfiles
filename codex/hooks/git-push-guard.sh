#!/usr/bin/env bash
# PreToolUse guard for Bash: block dangerous `git push` variants regardless of
# argument order (permission rules are prefix-matched and can be bypassed by
# placing flags/refspecs after an allowed prefix, e.g. `git push origin develop/x --force`).
#
# Tokenizes the command with shell-equivalent rules and inspects only arguments of
# a git invocation that stands in command position, so quoted text such as commit
# messages that merely mention "git push --force" does not false-positive.
set -o pipefail

cmd=$(jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

# Fast path: nothing resembling git+push anywhere -> allow. Case-insensitive
# because Windows resolves GIT.EXE the same as git.exe and the executable check
# below folds case; a case-sensitive gate here would shadow it.
printf '%s' "$cmd" | grep -qi 'git' || exit 0
printf '%s' "$cmd" | grep -qi 'push' || exit 0

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Tokenize with shell-equivalent rules. punctuation_chars makes shlex emit
# `;` `&&` `||` `|` `&` `(` `)` as tokens of their own even when no space
# surrounds them -- without it `cd /tmp; git push` yields the token `/tmp;` and
# the git that follows is mistaken for an argument.
# Newlines separate commands too, but shlex only treats them as whitespace, so
# they are rewritten to `;` first. Inside quotes that rewrite only alters the
# text of one token, which no decision depends on.
tokenize() { # $1=command string
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c '
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

# nocasematch covers the case folding that tr used to do, without a subprocess.
# Windows resolves GIT.EXE and git.exe alike, so every name test here is
# case-insensitive; ref and option tests below become case-insensitive too,
# which only widens what is denied.
shopt -s nocasematch

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
is_shell_exe() { # $1=token
  exe_name "$1"
  case "$exe_name_out" in
    sh|bash|zsh|dash|ksh|cmd|powershell|pwsh|su) return 0 ;;
  esac
  return 1
}

# Reduce a refspec to the ref it updates: drop a leading `+` (which forces a
# non-fast-forward update), keep the destination side of `src:dst`, and strip the
# fully qualified prefix. Without this, `+master`, `HEAD:master` and
# `refs/heads/master` all reach master while only the bare form is recognised.
dest_ref_out=""
dest_ref() { # $1=token -> dest_ref_out = the ref being updated
  local r="${1#+}"
  case "$r" in
    *:*) r="${r##*:}" ;;
  esac
  dest_ref_out="${r#refs/heads/}"
}

# Every argument of a push segment is checked exactly (not as a substring of
# quoted text).
check_segment() {
  local has_push=0 a take_next=0
  # git itself runs command strings: `submodule foreach`, `rebase --exec`,
  # `bisect run`. Quoted, the inner command is one token that never reaches the
  # push test, so it is scanned as a command line of its own.
  for a in "$@"; do
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
      foreach|--exec|-x|run) take_next=1 ;;
      # git's parse-options also accepts the joined form `--exec=<cmd>`.
      --exec=*|-x=*) scan_string "${a#*=}" ;;
    esac
  done
  for a in "$@"; do
    [ "$a" = "push" ] && has_push=1 && break
  done
  [ "$has_push" = 1 ] || return 0
  for a in "$@"; do
    case "$a" in
      # Long options may be abbreviated while they stay unambiguous, and short
      # options bundle (`-uf` is `-u -f`), so neither can be matched exactly.
      --force*|--f|--fo|--for|--forc) deny "git push の force 系 (--force/--force-with-lease/-f) はポリシーで禁止" ;;
      --delete|--del*|--de) deny "git push --delete/-d (リモートブランチ削除) はポリシーで禁止" ;;
      --mirror|--mir*|--mi|--all|--al|--prune|--pru*|--pr) deny "git push --mirror/--all/--prune はポリシーで禁止" ;;
      # Short options bundle (`-uf` is `-u -f`), so the whole cluster is grabbed
      # first and then inspected. Matching `-[A-Za-z]*f*` directly would let the
      # character class eat the only `f` and miss plain `-f`.
      -[A-Za-z]*)
        case "$a" in *f*) deny "git push の force 系 (--force/--force-with-lease/-f) はポリシーで禁止" ;; esac
        case "$a" in *d*) deny "git push --delete/-d (リモートブランチ削除) はポリシーで禁止" ;; esac
        ;;
      :?*) deny "空 refspec によるリモートブランチ削除 (git push origin :branch) はポリシーで禁止" ;;
      -*) ;;
      *)
        dest_ref "$a"
        # case, not [ ], so nocasematch applies: on Windows refs are files and a
        # differently cased name can reach the same ref, so MASTER is denied too.
        case "$dest_ref_out" in
          master) deny "master への push はポリシーで禁止" ;;
        esac
        ;;
    esac
  done
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

# Walk tokens tracking command position. Only a git token in command position
# opens a segment: `echo git push --force` mentions git in argument position and
# must stay allowed, while `cd /tmp; git push origin master` executes it after a
# separator and must not.
scan_tokens() {
  local at_cmd=1 in_git=0 shell_pending=0 wrapper_pending=0 redir_pending=0 eval_pending=0 t
  local seg=()
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
        [ "$in_git" = 1 ] && check_segment "${seg[@]}"
        in_git=0
        seg=()
        at_cmd=1
        shell_pending=0
        eval_pending=0
        wrapper_pending=0
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
            # that line away as if it were a filename.
            if [ "$shell_pending" != 0 ]; then
              shell_pending=2
              continue
            fi
            redir_pending=1
            continue
            ;;
        esac
        [ "$in_git" = 1 ] && check_segment "${seg[@]}"
        in_git=0
        seg=()
        at_cmd=1
        shell_pending=0
        eval_pending=0
        wrapper_pending=0
        continue
        ;;
    esac
    # After a wrapper, the command it runs is not necessarily the next token
    # (`timeout 30 git push`). Keep looking until this segment's git shows up;
    # tokens that are not git are the wrapper's own arguments.
    if [ "$wrapper_pending" = 1 ]; then
      if is_git_exe "$t"; then
        wrapper_pending=0
        at_cmd=0
        in_git=1
        seg=()
      elif is_shell_exe "$t"; then
        wrapper_pending=0
        shell_pending=1
        at_cmd=0
      fi
      continue
    fi
    # `sh -c <string>`: the string is a command line of its own, so scan it.
    # Waiting for the -c switch first, rather than taking the next non-option,
    # is what keeps `su someuser -c '<cmd>'` from consuming the user name as if
    # it were the command. cmd.exe spells it /c and PowerShell -Command.
    if [ "$shell_pending" = 1 ]; then
      case "$t" in
        -c|-[Cc]ommand|-EncodedCommand|/[Cc]|/[Kk]) shell_pending=2 ;;
      esac
      continue
    fi
    if [ "$shell_pending" = 2 ]; then
      shell_pending=0
      scan_string "$t"
      continue
    fi
    # eval joins its arguments back into one command line, so it is neither a
    # wrapper (the command may arrive quoted as a single token) nor a shell
    # taking exactly one string (it may arrive as separate words).
    if [ "$eval_pending" = 1 ]; then
      eval_pending=0
      case "$t" in
        *[[:space:]]*)
          scan_string "$t"
          continue
          ;;
      esac
      at_cmd=1
    fi
    if [ "$at_cmd" = 1 ]; then
      # A leading VAR=value assignment does not consume command position:
      # `GIT_DIR=/tmp/x git push --force` still executes git.
      case "$t" in
        [A-Za-z_]*=*) continue ;;
      esac
      case "$t" in
        eval) eval_pending=1; at_cmd=0; continue ;;
      esac
      # Shell keywords stand where a command stands but are not the command:
      # after `do` or `then` the real command follows. Consuming command
      # position here would leave `for r in ...; do git push --force` with git
      # in argument position.
      case "$t" in
        do|done|then|fi|else|elif|if|while|until|for|select|case|esac|in|function|"{"|"}"|"!"|time|coproc|exec|builtin)
          continue
          ;;
      esac
      if is_wrapper "$t"; then
        wrapper_pending=1
        continue
      fi
      if is_shell_exe "$t"; then
        shell_pending=1
        at_cmd=0
        continue
      fi
      at_cmd=0
      [ "$in_git" = 1 ] && check_segment "${seg[@]}"
      seg=()
      if is_git_exe "$t"; then in_git=1; else in_git=0; fi
      continue
    fi
    [ "$in_git" = 1 ] && seg+=("$t")
  done
  [ "$in_git" = 1 ] && check_segment "${seg[@]}"
  return 0
}

if ! scan_string "$cmd"; then
  # Could not be parsed at all. This path exists to fail closed, so it errs
  # toward denying: it covers every argument the exact check rejects.
  if printf '%s' "$cmd" | grep -Eqi -- '--force|--delete|--mirror|--all|--prune|(^|[[:space:]])-[A-Za-z]*[fd]|(^|[[:space:]:+])(refs/heads/)?master([[:space:]]|$)|[[:space:]]:[^[:space:]]'; then
    deny "git push コマンドを解析できず、危険な引数らしき文字列を含むためポリシーでブロック"
  fi
  exit 0
fi

exit 0
