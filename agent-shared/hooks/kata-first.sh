#!/usr/bin/env bash
# 利用者の入力ごとに、最初に開く skill を kata にする。kata の入口で、直接答えるか、どの skill や工程を
# 使うかを判断させるため。SessionStart の案内だけでは、すぐ答えられそうな質問で kata を飛ばすことがある。
#
#   prompt (UserPromptSubmit): そのセッションに「kata をまだ開いていない」印を付け、案内を出す。
#   pre    (PreToolUse):       印がある間は、kata を開く操作 (Skill・Read・Codex のコマンド)、タスク表示用のツール、回答を返すツールだけを通し、ほかは止める。
#
# 子エージェントのツール呼出し (agent_id がある) と、委譲された子のセッション (lib/delegated-session.sh) は
# 受け取った担当の範囲で進めるので対象外にする。
set -u

. "$(dirname "$0")/lib/delegated-session.sh"
in=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$in" 2>/dev/null)
[ -n "$sid" ] || exit 0
case $sid in *[!A-Za-z0-9._-]* | . | ..) exit 0 ;; esac

# 保存先は、自分が所有するシンボリックリンクでないディレクトリだけを使う。共有の一時領域で別ユーザーが
# 用意したディレクトリやリンクを使うと、印の書き込みがリンク先のファイルを空にするため。
# 既定の保存先を使えなければ一時領域を試し、どちらも使えなければ印を付けず案内だけにする。
# prompt と pre は同じ規則で同じ場所を選ぶ。
# 自分の所有を確かめたあとに権限を 700 にし、他人が中に印のリンクを作れない状態にしてから使う。
usable_dir() { mkdir -p "$1" 2>/dev/null && [ ! -L "$1" ] && [ -d "$1" ] && [ -O "$1" ] && chmod 700 "$1" 2>/dev/null && [ -w "$1" ]; }
state_dir=${KATA_FIRST_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-shared/kata-first}
if ! usable_dir "$state_dir"; then
  state_dir=${TMPDIR:-/tmp}/kata-first-$(id -u)
  usable_dir "$state_dir" || state_dir=
fi
pending=${state_dir:+$state_dir/$sid}
[ -n "$pending" ] && [ -L "$pending" ] && pending=

# kata の SKILL.md を指すパスか。Windows の区切り (\) と、kata のディレクトリへ移ってから読む形も受ける。
names_kata() { [[ $1 =~ skills[/\\]kata([/\\[:space:]]|$) && $1 == *SKILL.md* ]]; }

case ${1:-} in
  prompt)
    delegated_session "$sid" && exit 0
    # 案内は状態の保存に失敗しても出す。
    [ -n "$pending" ] && : > "$pending" 2>/dev/null
    jq -nc '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext:
      "<kata-first>この入力でも、最初に開く skill は kata にする。調査・真偽判定・方式選定・実装着手では、kata から investigation-discipline を開く。その手順で外部資料の本文を取り、手元の現物と照合してから結論・提案・実装に進む。</kata-first>"}}'
    ;;
  pre)
    [ -n "$pending" ] && [ -e "$pending" ] || exit 0
    # 判定は印があるときだけ行い、ツールを呼ぶたびに T3 の記録を引かない。
    delegated_session "$sid" && exit 0
    [ -n "$(jq -r '.agent_id // empty' <<<"$in")" ] && exit 0
    tool=$(jq -r '.tool_name // empty' <<<"$in")
    case $tool in
      mcp__ccd_turn__* | TaskCreate | TodoWrite | update_plan) exit 0 ;;
      # 回答を決まった形で返すだけのツール。skill を開くツールを持たない判定用の実行が、結果を返せなくなるため通す。
      StructuredOutput) exit 0 ;;
      Skill)
        if [ "$(jq -r '.tool_input.skill // empty' <<<"$in")" = kata ]; then
          rm -f "$pending"; exit 0
        fi ;;
      Read)
        if names_kata "$(jq -r '.tool_input.file_path // empty' <<<"$in")"; then
          rm -f "$pending"; exit 0
        fi ;;
      Bash)
        # Codex は skill の本文をコマンドで読む。kata の SKILL.md を読むコマンドを、kata を開いた操作とみなす。
        if names_kata "$(jq -r '.tool_input.command // empty' <<<"$in")"; then
          rm -f "$pending"; exit 0
        fi ;;
    esac
    echo "この入力では、まだ kata を開いていない。最初に kata skill を開き (Codex では kata の SKILL.md を読む)、その入口で直接答えるか、どの skill や工程を使うかを判断してから、このツールを使う。" >&2
    exit 2
    ;;
esac
exit 0
