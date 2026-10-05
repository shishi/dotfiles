#!/usr/bin/env bash
# UserPromptSubmit でターン開始点、PreToolUse で担当 path を記録し、
# Stop で依頼とその担当差分の必要性を独立評価する。
set -u

hook_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
action=${1:-}
hook_input=$(cat)
cwd=$(printf '%s' "$hook_input" | jq -r '.cwd // ""')

repo=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || {
  printf '{}\n'
  exit 0
}
git_dir=$(git -C "$repo" rev-parse --absolute-git-dir 2>/dev/null) || {
  printf '{}\n'
  exit 0
}

session_id=$(printf '%s' "$hook_input" | jq -r '.session_id // "session"')
turn_id=$(printf '%s' "$hook_input" | jq -r '.turn_id // "turn"')
session_key=$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9._-')
turn_key=$(printf '%s' "$turn_id" | tr -cd 'A-Za-z0-9._-')
[ -n "$session_key" ] || session_key=session
[ -n "$turn_key" ] || turn_key=turn
key="$session_key-$turn_key"
state_root="$git_dir/codex-task-necessity"
state_dir="$state_root/$key"

cleanup_dir() {
  local dir="$1"
  rm -f -- "$dir/head" "$dir/prompt" "$dir/initial.diff" "$dir/initial.untracked" \
    "$dir/review.prompt" "$dir/review.result" "$dir/blocks" "$dir/paths" "$dir/transcript-lines"
  rmdir "$dir" 2>/dev/null || true
  rmdir "$state_root" 2>/dev/null || true
}

cleanup() { cleanup_dir "$state_dir"; }

cleanup_session() {
  local keep=${1:-}
  for old_state in "$state_root/$session_key-"*; do
    [ -d "$old_state" ] || continue
    [ -n "$keep" ] && [ "$old_state" = "$keep" ] && continue
    cleanup_dir "$old_state"
  done
}

case "$action" in
  start)
    submitted_prompt=$(printf '%s' "$hook_input" | jq -r '.prompt // ""')
    if printf '%s' "$hook_input" | jq -e '.agent_id != null' >/dev/null; then
      # subagent の turn は親の依頼 state を作り直さない。担当 path は track で
      # session 内に一つだけある親 state へ集約する。
      printf '{}\n'
      exit 0
    fi
    if [[ "$submitted_prompt" = '<hook_prompt'* ]]; then
      # Stop hook の再試行は擬似 user message として届く。state の有無にかかわらず、
      # 内部指摘をユーザー依頼として記録しない。
      printf '{}\n'
      exit 0
    fi
    # 同じ session で前の turn が中断されていれば、別 session へ触れず既知 state だけ掃除する。
    cleanup_session "$state_dir"
    umask 077
    mkdir -p "$state_dir" || {
      printf '{}\n'
      exit 0
    }
    git -C "$repo" rev-parse HEAD >"$state_dir/head" || {
      cleanup
      printf '{}\n'
      exit 0
    }
    printf '%s' "$submitted_prompt" >"$state_dir/prompt"
    git -C "$repo" diff --no-ext-diff --binary HEAD -- . >"$state_dir/initial.diff"
    git -C "$repo" ls-files --others --exclude-standard | sort >"$state_dir/initial.untracked"
    : >"$state_dir/paths"
    : >"$state_dir/review.result"
    transcript_path=$(printf '%s' "$hook_input" | jq -r '.transcript_path // ""')
    if [ -f "$transcript_path" ]; then
      wc -l <"$transcript_path" >"$state_dir/transcript-lines"
    else
      printf '0\n' >"$state_dir/transcript-lines"
    fi
    printf '{}\n'
    ;;

  track)
    if [ ! -f "$state_dir/paths" ] &&
      printf '%s' "$hook_input" | jq -e '.agent_id != null' >/dev/null; then
      parent_state=""
      parent_state_count=0
      for candidate in "$state_root/$session_key-"*; do
        [ -f "$candidate/paths" ] || continue
        parent_state=$candidate
        parent_state_count=$((parent_state_count + 1))
      done
      [ "$parent_state_count" -eq 1 ] && state_dir=$parent_state
    fi
    [ -f "$state_dir/paths" ] || {
      printf '{}\n'
      exit 0
    }
    repo_prefix=$(git -C "$cwd" rev-parse --show-prefix 2>/dev/null) || {
      printf '{}\n'
      exit 0
    }
    record_path() {
      local path=$1
      case "$path" in
        "$repo"/*) path=${path#"$repo"/} ;;
        /*) return ;;
        *) path="${repo_prefix}${path#./}" ;;
      esac
      case "$path" in
        ''|.|..|../*|*/../*|*/..|./*|*/./*) return ;;
      esac
      printf '%s\n' "$path" >>"$state_dir/paths"
    }
    umask 077
    while IFS= read -r path; do
      [ -n "$path" ] && record_path "$path"
    done < <(printf '%s' "$hook_input" | jq -r '
      .tool_input as $input |
      if ($input | type) == "object" then
        ($input.file_path // $input.path // empty),
        (($input.edits // [])[]? | .file_path // .path // empty)
      else empty end
    ')
    patch_input=$(printf '%s' "$hook_input" | jq -r '
      .tool_input as $input |
      if ($input | type) == "string" then $input
      elif ($input | type) == "object" then ($input.command // $input.patch // $input.input // "")
      else "" end
    ')
    while IFS= read -r line; do
      case "$line" in
        '*** Add File: '*) record_path "${line#\*\*\* Add File: }" ;;
        '*** Update File: '*) record_path "${line#\*\*\* Update File: }" ;;
        '*** Delete File: '*) record_path "${line#\*\*\* Delete File: }" ;;
      esac
    done <<<"$patch_input"
    printf '{}\n'
    ;;

  stop)
    [ -f "$state_dir/head" ] && [ -f "$state_dir/prompt" ] &&
      [ -f "$state_dir/initial.diff" ] && [ -f "$state_dir/initial.untracked" ] &&
      [ -f "$state_dir/paths" ] || {
      printf '{}\n'
      exit 0
    }
    # 他の Stop hook がこの応答を差し戻す可能性があるため、自分が PASS しても
    # 元依頼は次の実 user prompt まで保持する。
    trap cleanup HUP INT TERM

    start_head=$(cat "$state_dir/head")
    current_diff=$(git -C "$repo" diff --no-ext-diff --binary "$start_head" -- . 2>/dev/null) || {
      printf '{}\n'
      exit 0
    }
    initial_diff=$(cat "$state_dir/initial.diff")
    initial_untracked=$(cat "$state_dir/initial.untracked")
    current_untracked=$(git -C "$repo" ls-files --others --exclude-standard | sort)
    transcript_path=$(printf '%s' "$hook_input" | jq -r '.transcript_path // ""')
    conversation_context='{"messages":[],"unavailable":true}'
    tool_evidence='{"calls":[],"unavailable":true}'
    if [ -f "$transcript_path" ]; then
      transcript_lines=$(cat "$state_dir/transcript-lines" 2>/dev/null) || transcript_lines=0
      # ユーザー直近20件と assistant 直近10件を別々に選び、再応答で依頼の前提が押し出されるのを防ぐ。
      # 各2000文字、ツールは直近30件・入力1200文字・結果4000文字まで。
      # 省略を明示し、結果が見えないことを未実施と誤認させない。thinking は渡さない。
      evidence=$(jq -cs --argjson start "$transcript_lines" '
        def text_content:
          if type == "string" then .
          elif type == "array" then map(.text? // "") | join("\n")
          elif type == "object" then tojson
          else "" end;
        def external_text:
          select(. != "" and (ltrimstr("\n") | startswith("<hook_prompt") | not));
        to_entries | map(.key as $line | .value | select(.isSidechain != true) |
          if .type == "user" and .isMeta != true then
            if (.message.content | type) == "string" then
              {kind:"message",role:"user",text:(.message.content | external_text)}
            else .message.content[]? |
              if .type == "text" then
                {kind:"message",role:"user",text:(.text | external_text)}
              elif .type == "tool_result" then
                {kind:"result",id:.tool_use_id,output:(.content | text_content),is_error:(.is_error // false)}
              else empty end
            end
          elif .type == "assistant" then .message.content[]? |
            if .type == "text" then {kind:"message",role:"assistant",text:.text}
            elif .type == "tool_use" then
              {kind:"call",id:.id,tool:.name,input:(.input | tojson),line:$line}
            else empty end
          elif .type == "event_msg" and .payload.type == "user_message" then
            {kind:"message",role:"user",text:(.payload.message | text_content | external_text)}
          elif .type == "response_item" then .payload |
            if .type == "message" and (.role == "user" or .role == "assistant") then
              .role as $role | .internal_chat_message_metadata_passthrough.content_item_kinds as $kinds |
              .content | to_entries[] |
              select($role == "assistant" or $kinds == null or $kinds[.key] == "user.text") |
              {kind:"message",role:$role,text:(.value.text // "" | external_text)}
            elif .type == "function_call" or .type == "custom_tool_call" then
              {kind:"call",id:.call_id,tool:.name,input:(.arguments // .input // "" | text_content),line:$line}
            elif .type == "function_call_output" or .type == "custom_tool_call_output" then
              {kind:"result",id:.call_id,output:(.output | text_content)}
            else empty end
          else empty end
        ) |
        reduce .[] as $event ({messages:[],calls:[],results:{}};
          if $event.kind == "message" then
            ($event | del(.kind)) as $message |
            if .messages[-1] == $message then . else .messages += [$message] end
          elif $event.kind == "call" then .calls += [$event]
          elif $event.kind == "result" and $event.id != null then .results[$event.id] = $event
          else . end
        )
        | .results as $results |
        (.messages | to_entries |
          (map(select(.value.role == "user"))[-20:] +
           map(select(.value.role == "assistant"))[-10:]) |
          sort_by(.key) | map(.value)) as $messages |
        {conversation:{truncated:((.messages | length) > ($messages | length)), messages:($messages |
            map(. + {truncated:(.text | length > 2000)} | .text = .text[:2000]))},
         tools:{truncated:(.calls | length > 30), calls:(.calls[-30:] | map(
            ($results[.id // ""] // null) as $result |
            {id:.id,tool:.tool,input:.input[:1200],
             scope:(if .line >= $start then "current" else "prior" end),
             output:($result.output // null | if . == null then null else .[:4000] end),
             is_error:$result.is_error,
             result_missing:($result == null),
             truncated:((.input | length > 1200) or ($result.output // "" | length > 4000))}
         ))}}
      ' "$transcript_path" 2>/dev/null) || evidence=""
      if [ -n "$evidence" ]; then
        conversation_context=$(printf '%s' "$evidence" | jq -c '.conversation')
        tool_evidence=$(printf '%s' "$evidence" | jq -c '.tools')
      fi
    fi
    owned_paths=()
    while IFS= read -r path; do
      [ -n "$path" ] && owned_paths+=("$path")
    done < <(sort -u "$state_dir/paths")

    filter_owned_paths() {
      local candidates=$1 path filtered=""
      for path in "${owned_paths[@]}"; do
        if printf '%s\n' "$candidates" | grep -Fqx -- "$path"; then
          filtered="${filtered}${filtered:+$'\n'}${path}"
        fi
      done
      printf '%s' "$filtered"
    }
    initial_untracked=$(filter_owned_paths "$initial_untracked")
    current_untracked=$(filter_owned_paths "$current_untracked")

    # shared worktree 全体ではなく、この親 session と turn の PreToolUse が記録した
    # path だけを reviewer へ渡す。subagent は親 session_id 内で唯一の親 state へ
    # 集約し、独立 session の path は別 state に分離する。
    turn_diff=""
    if [ "${#owned_paths[@]}" -gt 0 ] && tmp_index=$(mktemp 2>/dev/null); then
      turn_diff=$(
        export GIT_INDEX_FILE="$tmp_index"
        git -C "$repo" read-tree "$start_head" 2>/dev/null || exit 1
        if [ -n "$initial_diff" ]; then
          printf '%s\n' "$initial_diff" | git -C "$repo" apply --cached - 2>/dev/null || exit 1
        fi
        tree_initial=$(git -C "$repo" write-tree 2>/dev/null) || exit 1
        git -C "$repo" read-tree "$start_head" 2>/dev/null || exit 1
        if [ -n "$current_diff" ]; then
          printf '%s\n' "$current_diff" | git -C "$repo" apply --cached - 2>/dev/null || exit 1
        fi
        tree_current=$(git -C "$repo" write-tree 2>/dev/null) || exit 1
        GIT_LITERAL_PATHSPECS=1 git -C "$repo" diff --no-ext-diff \
          "$tree_initial" "$tree_current" -- "${owned_paths[@]}" 2>/dev/null
      ) || turn_diff=""
      rm -f -- "$tmp_index"
    fi

    review_rules=$(cat "$hook_dir/prompts/task-necessity-review.txt" 2>/dev/null) || review_rules=""
    previous_review=$(cat "$state_dir/review.result" 2>/dev/null) || previous_review=""
    {
      printf '%s\n' "$review_rules"
      printf '\n<previous-review>\n%s\n</previous-review>\n' "$previous_review"
      printf '\n<user-request>\n%s\n</user-request>\n' "$(cat "$state_dir/prompt")"
      printf '\n<assistant-response>\n%s\n</assistant-response>\n' "$(printf '%s' "$hook_input" | jq -r '.last_assistant_message // ""')"
      printf '\n<conversation-context>\n%s\n</conversation-context>\n' "$conversation_context"
      printf '\n<tool-evidence>\n%s\n</tool-evidence>\n' "$tool_evidence"
      printf '\n<transcript-path>\n%s\n</transcript-path>\n' "$transcript_path"
      if [ -n "$turn_diff" ]; then
        printf '\n<task-owned-diff>\n%s\n</task-owned-diff>\n' "$turn_diff"
      fi
      printf '\n<initial-task-owned-untracked-paths>\n%s\n</initial-task-owned-untracked-paths>\n' "$initial_untracked"
      printf '\n<current-task-owned-untracked-paths>\n%s\n</current-task-owned-untracked-paths>\n' "$current_untracked"
    } >"$state_dir/review.prompt"

    feedback_instruction='内部是正。依頼者はユーザー。指摘は採否判断し元依頼を維持。必要な構造は残し不要だけ削除。正当な回答内提案は差分ではなく、削除・撤回・実装要求の対象外。受領・同意・反省・謝罪・決意・是正実況は途中報告にも最終回答にも出すな。hook の指摘への返答を主文にせず、元のユーザー依頼に対して実行したこと、結果、未完了事項を報告。自力でできる残件は実行・検証し、未確認への言い換えや隠蔽で終えるな。停止の根拠は当該ターンで確認し、可能な独立作業を済ませて具体的障害と本人に必要な操作・判断だけを示せ。'
    codex_bin=${CODEX_BIN_PATH:-codex}
    : >"$state_dir/review.result"
    if [ -z "$review_rules" ] || ! "$codex_bin" exec -C "$repo" -s read-only --ignore-user-config \
      --disable hooks --ephemeral -m gpt-5.6-luna -c model_reasoning_effort='"low"' \
      --color never -o "$state_dir/review.result" - \
      <"$state_dir/review.prompt" >/dev/null 2>&1; then
      jq -n --arg feedback "$feedback_instruction" --rawfile request "$state_dir/prompt" \
        '{decision:"block",reason:($feedback + "\n検査失敗: 判定規約を読み込めないか、判定コマンドが失敗した。回答内容の不適合と混同せず、検査の実行環境を確認して再試行せよ。\n\n元のユーザー依頼:\n" + $request)}'
      exit 0
    fi

    verdict=$(sed -n '1p' "$state_dir/review.result")
    if [[ "$verdict" =~ ^BLOCK($|[[:space:]:]) ]]; then
      reason=$(
        {
          printf '%s\n' "${verdict#BLOCK}"
          sed '1d' "$state_dir/review.result"
        } | sed '1s/^[:： ]*//'
      )
      [ -n "$reason" ] || reason='依頼または観測済み障害に直接対応しない構造が差分に含まれている。'
      # 元の依頼と state を保持し、再応答も同じ reviewer に通す。
      original_request=$(cat "$state_dir/prompt")
      guidance=$(printf '\n元のユーザー依頼:\n%s' "$original_request")
      jq -n --arg feedback "$feedback_instruction" --arg reason "$reason" --arg guidance "$guidance" \
        '{decision:"block", reason:($feedback + "\n" + $reason + "\n" + $guidance)}'
    elif [[ "$verdict" =~ ^PASS($|[[:space:]:]) ]]; then
      printf '{}\n'
    else
      jq -n --arg feedback "$feedback_instruction" --rawfile request "$state_dir/prompt" \
        '{decision:"block",reason:($feedback + "\n検査失敗: 判定出力が空または形式不正。合格とは扱わず、検査の出力を確認して再試行せよ。\n\n元のユーザー依頼:\n" + $request)}'
    fi
    ;;

  cleanup-session)
    cleanup_session
    printf '{}\n'
    ;;

  *)
    printf '{}\n'
    ;;
esac
