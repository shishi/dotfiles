#!/usr/bin/env bash
# PreToolUse guard for Bash: block dangerous `git push` variants regardless of
# argument order (permission rules are prefix-matched and can be bypassed by
# placing flags/refspecs after an allowed prefix, e.g. `git push origin develop/x --force`).
#
# Tokenizes the command (quote-aware via xargs) and inspects only arguments of
# an actual `git ... push` invocation, so quoted text such as commit messages
# that merely mention "git push --force" does not false-positive.
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
tokenize() {
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$cmd" | python3 -c '
import sys, shlex
try:
    for t in shlex.split(sys.stdin.read(), posix=True):
        print(t)
except ValueError:
    sys.exit(1)
' | tr -d '\r'
  else
    printf '%s' "$cmd" | xargs -n1 printf '%s\n' 2>/dev/null
  fi
}

tokens=()
if toklist=$(tokenize); then
  while IFS= read -r t; do tokens+=("$t"); done <<< "$toklist"
else
  if printf '%s' "$cmd" | grep -Eq -- '--force|--delete|--mirror|(^|[[:space:]:])master([[:space:]]|$)'; then
    deny "git push コマンドを解析できず、危険な引数らしき文字列を含むためポリシーでブロック"
  fi
  exit 0
fi

# Walk tokens; a "git segment" runs from a `git` token to the next shell
# separator. Inside a segment that contains the `push` subcommand, every
# argument is checked exactly (not as substring of quoted text).
in_git=0
seg=()
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
      master|*:master) deny "master への push はポリシーで禁止" ;;
      :?*) deny "空 refspec によるリモートブランチ削除 (git push origin :branch) はポリシーで禁止" ;;
    esac
  done
  return 0
}

for t in "${tokens[@]}"; do
  case "$t" in
    "&&"|"||"|";"|"|"|"&"|"("|")")
      [ "$in_git" = 1 ] && check_segment "${seg[@]}"
      in_git=0
      seg=()
      ;;
    git)
      in_git=1
      seg=()
      ;;
    *)
      [ "$in_git" = 1 ] && seg+=("$t")
      ;;
  esac
done
[ "$in_git" = 1 ] && check_segment "${seg[@]}"

exit 0
