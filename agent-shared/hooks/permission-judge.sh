#!/usr/bin/env bash
# PermissionRequest (Claude Code): auto mode でも出る確認画面に、利用者の代わりに許可か拒否で答える。
#
# 普段の判定は auto mode の分類器が行い、この hook は呼ばれない。呼ばれるのは確認画面が出る直前で、
# 分類器とは別の組み込みの検査 (保護されたパスに対する rm、symlink された設定ファイルの実体への書き込み、
# sandbox の外での実行など) が出す場合と、分類器が拒否を重ねて auto mode が確認画面に戻った場合がある。
# どちらも判定役 (claude -p) に、分類器と同じ実効ルール (`claude auto-mode config`) と利用者の発言を見せて
# 決めさせる。分類器が止めた操作を、ルールの狭い判定役が通さないようにするため。キャッシュ・一時ディレクトリ内の
# 狭い対象の削除は作り直せるものなので、作成の記録が無くても許可するよう指示している。
#
# 判定役には利用者の発言、エージェントのこれまでのツール呼び出し、保留中の操作を渡し、アシスタントの文章と
# ツールの結果は渡さない (auto mode の分類器と同じ。ツールの結果に紛れ込んだ指示に判定を引きずられないため)。
# 過去の呼び出しは、削除対象をエージェント自身が作ったかなどを判定役が確かめるのに要る。判定役が答えられないときも確認画面は
# 出さず拒否する。hook 自体が失敗したときは settings.json の onFailure: "block" で同じく実行させない。
set -o pipefail

hook_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# 実測の所要時間は 3.0〜5.4 秒 (ルール一式と長い会話記録を渡した場合を含む)。通信の揺れを見込んで十分に長くとる。
# hook 自体の上限は 90 秒。
judge_timeout_seconds=75

decide() {
  if [ "$1" = allow ]; then
    jq -cn '{hookSpecificOutput: {hookEventName: "PermissionRequest", decision: {behavior: "allow"}}}'
  else
    jq -cn --arg m "[permission-judge] $2" \
      '{hookSpecificOutput: {hookEventName: "PermissionRequest", decision: {behavior: "deny", message: $m}}}'
  fi
  exit 0
}

input=$(cat) || decide deny "hook の入力を読めなかった。"
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty') || decide deny "hook の入力が JSON でない。"
# 利用者への質問と計画の承認は、確認画面ではなく利用者との対話なので判定しない (判定を返さず通常の表示に任せる)。
case $tool in AskUserQuestion|ExitPlanMode) exit 0 ;; esac

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
call=$(printf '%s' "$input" | jq -c '{tool_name, tool_input}')
context=$(jq -cn --arg cwd "$cwd" --arg home "$HOME" --arg mode "$(printf '%s' "$input" | jq -r '.permission_mode // empty')" \
  '{working_directory: $cwd, home_directory: $home, permission_mode: $mode}')

# 利用者が自分で入力した発言と、エージェントのツール呼び出しを記録順に並べる。委譲先からの報告 (origin が peer)、
# ツールの結果、アシスタントの文章は含めない。作業中に送られた発言は user の行ではなく queued_command の添付として
# 残るため、両方を拾う。ツール呼び出しの入力は長いファイル本文を含みうるので、呼び出しごとに先頭 500 文字に縮める。
# 読めない行はその行だけ飛ばす (書き込み途中の行で以降の記録まで失わないため)。
read_history() {
  jq -Rr 'fromjson? |
      def text: if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join("\n")) end;
      if .type == "user" and .origin.kind == "human" then
        "- [user] " + (.message.content | text)
      elif .type == "attachment" and .attachment.type == "queued_command" and .attachment.origin.kind == "human" then
        "- [user] " + (.attachment.prompt | text)
      elif .type == "assistant" then
        .message.content[]? | select(.type == "tool_use") | "- [agent call] " + .name + " " + (.input | tojson | .[0:500])
      else empty end' "$1"
}
history=""
if [ -n "$transcript" ] && [ -r "$transcript" ]; then
  history=$(read_history "$transcript") || decide deny "会話記録を読み出せなかった。"
  # subagent の中の確認画面では、subagent 自身のツール呼び出しが別の記録 (<session>/subagents/agent-<id>.jsonl) に
  # 残る。利用者の発言は親の記録から取り、subagent の呼び出しを後ろに足す。
  agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty')
  sub="${transcript%.jsonl}/subagents/agent-${agent_id#agent-}.jsonl"
  if [ -n "$agent_id" ] && [ -r "$sub" ]; then
    sub_calls=$(read_history "$sub") || decide deny "subagent の会話記録を読み出せなかった。"
    history=$(printf '%s\n%s' "$history" "$(printf '%s\n' "$sub_calls" | grep -v '^- \[user\] ' || true)")
  fi
  # 承認と撤回は会話のどこにあっても有効なので、利用者の発言は全部残す。長い会話で判定役の入力上限を超えないよう、
  # ツール呼び出しだけを古いものから捨てて 300000 バイトに収める。
  history=$(printf '%s\n' "$history" | LC_ALL=C awk -v limit=300000 '
      { line[NR] = $0; size += length($0) + 1 }
      END {
        for (i = 1; i <= NR && size > limit; i++)
          if (line[i] ~ /^- \[agent call\] /) { size -= length(line[i]) + 1; line[i] = "" ; drop[i] = 1 }
        for (i = 1; i <= NR; i++) if (!drop[i]) print line[i]
      }')
fi

# 分類器が実際に使うルール一式。利用者設定の autoMode (agent-shared/policy/action-policy.json から生成) を含む。
rules=$(claude auto-mode config 2>/dev/null | jq -r '
    [["ENVIRONMENT", .environment], ["ALLOW", .allow], ["SOFT DENY", .soft_deny], ["HARD DENY", .hard_deny]][]
    | "### " + .[0], (.[1][] | "- " + .)') || decide deny "auto mode のルール一式を取得できなかった。"
# 指示とルールは呼び出しごとに変わらないので system prompt に置き、判定役の入力キャッシュに載せる。
# 100KB 近くあり、引数で渡すと Windows のコマンドライン長の上限を超えるため、一時ファイルで渡す。
system_prompt_file=$(mktemp "${TMPDIR:-/tmp}/permission-judge.XXXXXX") || decide deny "一時ファイルを作れなかった。"
trap 'rm -f "$system_prompt_file"' EXIT
printf '%s\n\n## RULES\n%s\n' "$(cat "$hook_dir/permission-judge-prompt.md")" "$rules" > "$system_prompt_file" ||
  decide deny "判定役の指示を書き出せなかった。"

py_bin=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c '' >/dev/null 2>&1; then
    py_bin=$candidate
    break
  fi
done
[ -n "$py_bin" ] || decide deny "判定役の締切を管理する python が見つからなかった。"

schema='{"type":"object","properties":{"decision":{"type":"string","enum":["allow","deny"]},"reason":{"type":"string"}},"required":["decision","reason"],"additionalProperties":false}'

# 判定役が正常に終わり、成功の結果を返したときだけ判定を採用する。締切は run-judge.py が管理し、
# 締切を過ぎたらプロセスツリーごと止める (timeout コマンドの無い環境や、孫プロセスが残る Windows のため)。
result=$(printf '## CONTEXT\n%s\n\n## TRANSCRIPT\n%s\n\n## PENDING CALL\n%s\n' "$context" "${history:-(none)}" "$call" |
  "$py_bin" -I "$hook_dir/lib/run-judge.py" "$judge_timeout_seconds" "${cwd:-.}" \
    claude -p --model sonnet --setting-sources "" --strict-mcp-config --tools "" --no-session-persistence \
    --system-prompt-file "$system_prompt_file" --json-schema "$schema" --output-format json 2>/dev/null) ||
  decide deny "判定役 (claude -p) が失敗したため、確認画面を出さずに拒否した。"
# 出力全体が 1 つの正常な JSON の結果であるときだけ判定を読む (途中まで読めた結果を採用しないため)。
verdict=$(printf '%s' "$result" |
  jq -cs 'if length == 1 and .[0].is_error == false and .[0].subtype == "success"
          then .[0].structured_output // empty else empty end' 2>/dev/null) ||
  decide deny "判定役 (claude -p) の出力を読めなかったため、確認画面を出さずに拒否した。"

decision=$(printf '%s' "$verdict" | jq -r '.decision // empty' 2>/dev/null)
reason=$(printf '%s' "$verdict" | jq -r '.reason // empty' 2>/dev/null)
case $decision in
  allow) decide allow ;;
  deny) decide deny "$reason" ;;
  *) decide deny "判定役 (claude -p) が判定を返さなかったため、確認画面を出さずに拒否した。" ;;
esac
