#!/usr/bin/env bash
# 応答の文体ルールを Stop 時に完全ローカル(ミリ秒)で検査する。
# LLM は呼ばない(codex は方針で不可、claude -p は起動だけで 30 秒超を実測)。
# 個別語の列挙も持たない — 規則を直接機械化する:
#   1. コード表記(``` フェンスと `...`)の外にある ASCII 略語は、ユーザー自身が
#      使った語か、応答内で「語(説明)」の形で初出定義していなければブロック
#      (= 初出で定義しない語を使わない)
#   2. 判断をユーザーへ投げ返す言い回しがあればブロック(= 選択肢メニュー禁止)
set -u

hook_input=$(cat)

if [ "$(printf '%s' "$hook_input" | jq -r '.stop_hook_active // false')" = true ]; then
  printf '{}\n'
  exit 0
fi

last=$(printf '%s' "$hook_input" | jq -r '.last_assistant_message // ""')
transcript=$(printf '%s' "$hook_input" | jq -r '.transcript_path // ""')
{ [ -n "$last" ] && [ -f "$transcript" ]; } || {
  printf '{}\n'
  exit 0
}

# コードフェンスとバッククォート表記(コード識別子・コマンドは対象外)を除去
stripped=$(printf '%s\n' "$last" | awk '/^ *```/{fence=!fence;next} !fence' | sed -E 's/`[^`]*`//g')

# ユーザーが自分の発言で使った語は共有語彙として対象外にする
user_text=$(jq -rs '
  [ .[] | select(.type == "user") | .message.content
    | if type == "string" then . else (map(.text? // "") | join("\n")) end ]
  | join("\n")' "$transcript" 2>/dev/null)

violations=""
for term in $(printf '%s' "$stripped" | grep -oE '\b[A-Z][A-Z0-9]{2,7}\b' | sort -u); do
  printf '%s' "$user_text" | grep -qiF -- "$term" && continue
  printf '%s' "$stripped" | grep -qE -- "${term}[((]" && continue
  violations="$violations $term"
done

menu=$(printf '%s' "$stripped" | grep -oE 'どれにする|どちらにする|どっちにする|選んでね|どうする[?？]' | sort -u | tr '\n' ' ')

if [ -z "$violations" ] && [ -z "$menu" ]; then
  printf '{}\n'
  exit 0
fi

reason=""
[ -z "$violations" ] || reason="初出で定義していない語:${violations}(平易な日本語に置き換えるか、初出で「語(説明)」の形で定義する)"
[ -z "$menu" ] || reason="${reason}${reason:+ / }判断を投げ返す言い回し: ${menu}(選択肢を並べず、自分の判断で進めて結果を報告する)"
jq -n --arg reason "$reason" \
  '{decision:"block", reason:("応答スタイル違反: " + $reason + "\n書き換えて応答し直せ。")}'
