#!/usr/bin/env bash
# PreToolUse guard for Bash: block dangerous `git push` variants regardless of
# argument order (permission rules are prefix-matched and can be bypassed by
# placing flags/refspecs after an allowed prefix, e.g. `git push origin develop/x --force`).
#
# Tokenizes the command (quote-aware via shlex) and inspects only arguments of a
# git invocation that stands in command position, so quoted text such as commit
# messages that merely mention "git push --force" does not false-positive.
set -o pipefail

cmd=$(jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

# Fast path: nothing resembling git+push anywhere -> allow
printf '%s' "$cmd" | grep -q 'git' || exit 0
printf '%s' "$cmd" | grep -q 'push' || exit 0

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Quote-aware tokenization: shell-equivalent rules via Python shlex (xargs
# cannot handle e.g. an apostrophe inside a double-quoted string). If the
# command cannot be parsed at all, fall back to a conservative raw scan.
tokenize() { # $1=command string
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c '
import sys, shlex
try:
    for t in shlex.split(sys.stdin.read(), posix=True):
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
# basename so every execution form is recognised, and strip both separators
# because a Windows path can reach us either way.
is_git_exe() { # $1=token
  local base
  base="${1##*/}"
  base="${base##*\\}"
  case "$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')" in
    git|git.exe) return 0 ;;
  esac
  return 1
}

# Every argument of a push segment is checked exactly (not as a substring of
# quoted text).
check_segment() {
  local has_push=0 a
  for a in "$@"; do
    [ "$a" = "push" ] && has_push=1 && break
  done
  [ "$has_push" = 1 ] || return 0
  for a in "$@"; do
    case "$a" in
      --force*|-f) deny "git push の force 系 (--force/--force-with-lease/-f) はポリシーで禁止" ;;
      --delete|-d) deny "git push --delete/-d (リモートブランチ削除) はポリシーで禁止" ;;
      --mirror|--all|--prune) deny "git push --mirror/--all/--prune はポリシーで禁止" ;;
      # 保護先 master は refspec 変形でも同じ結果になる: HEAD:master・+master
      # (leading + は non-fast-forward を強制するので --force と同じ効果)。
      master|+master|*:master) deny "master への push はポリシーで禁止" ;;
      :?*) deny "空 refspec によるリモートブランチ削除 (git push origin :branch) はポリシーで禁止" ;;
    esac
  done
  return 0
}

# Walk tokens tracking command position. Only a git token in command position
# opens a segment: `echo git push --force` mentions git in argument position and
# must stay allowed, while `cd /tmp && /usr/bin/git push origin master` executes
# it after a separator and must not.
scan_tokens() {
  local at_cmd=1 in_git=0 t
  local seg=()
  for t in "$@"; do
    case "$t" in
      "&&"|"||"|";"|"|"|"&"|"("|")")
        [ "$in_git" = 1 ] && check_segment "${seg[@]}"
        in_git=0
        seg=()
        at_cmd=1
        continue
        ;;
    esac
    if [ "$at_cmd" = 1 ]; then
      # A leading VAR=value assignment does not consume command position:
      # `GIT_DIR=/tmp/x git push --force` still executes git.
      case "$t" in
        [A-Za-z_]*=*) continue ;;
      esac
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

scan_string() { # $1=command string; returns 1 when it cannot be tokenized
  local toklist t
  local toks=()
  toklist=$(tokenize "$1") || return 1
  while IFS= read -r t; do toks+=("$t"); done <<< "$toklist"
  scan_tokens "${toks[@]}"
  return 0
}

if ! scan_string "$cmd"; then
  if printf '%s' "$cmd" | grep -Eq -- '--force|--delete|--mirror|(^|[[:space:]:+])master([[:space:]]|$)'; then
    deny "git push コマンドを解析できず、危険な引数らしき文字列を含むためポリシーでブロック"
  fi
  exit 0
fi

# The inside of a command substitution is also command position, but shlex keeps
# `$(git` glued to the token before it. Rewrite the substitution punctuation into
# separators and scan again, so the substituted command starts a segment of its
# own. Nesting needs no recursion: every level is rewritten in the same pass.
case "$cmd" in
  *'$('*|*'`'*)
    subst=$(printf '%s' "$cmd" | sed 's/\$(/ ; /g; s/`/ ; /g; s/)/ ; /g')
    scan_string "$subst" || exit 0
    ;;
esac

exit 0
