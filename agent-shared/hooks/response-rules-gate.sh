#!/usr/bin/env bash
# 応答の文体ルールを Stop 時に検査する:
#   1. コード表記の外の ASCII 略語は、ユーザー自身が使った語か、応答内で
#      「語(説明)」の形で初出定義していなければブロック
#   2. 判断をユーザーへ投げ返す言い回しがあればブロック
# 共有 hook(Claude Code / codex)なので片方にしかないコマンドへ依存しない。
# transcript が読めない環境では素通しになる。
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

# ユーザーが直前の発言で矛盾・誤りを指摘しているターンでは、応答に
# 「当時知っていたか / 間違いだったか」への事実の表明を必ず含めさせる。
# 表明を飛ばして整合の説明だけを組み立てる応答(後付けの抵抗)をブロックする。
evasion=""
last_user=$(jq -rs '
  [ .[] | select(.type == "user") | .message.content
    | if type == "string" then . else (map(select(.type? == "text") | .text) | join("\n")) end
    | select(. != "") ]
  | last // ""' "$transcript" 2>/dev/null)
if printf '%s' "$last_user" | grep -qE 'くせに|矛盾|往生際|うそ|嘘|いったよね|言ったよね|言ってたのに'; then
  printf '%s' "$stripped" | grep -qE '知らな(かった|い)|知りませんでした|わかっていな(かった|い)|分かっていな(かった|い)|把握していな(かった|い)|間違(い|って)|誤り|その通り|当時から知って' || \
    evasion="矛盾・誤りの指摘には、まず「当時知っていたか / 間違いだったか」を事実で答える。整合の説明を書くなら、後付けなら後付けと明示してから"
fi

# 口調: 長めの応答に砕けた語尾が一つも無いときは報告書モードに落ちている
tone=""
prose_bytes=$(printf '%s' "$stripped" | tr -d '[:space:]' | wc -c)
if [ "$prose_bytes" -ge 300 ]; then
  printf '%s' "$stripped" | grep -qE 'アタシ|だよ|だね|じゃん|っしょ|よ〜|ね〜|よ。|ね。|よ!|ね!|かな。' || \
    tone="口調が報告書モードに落ちている(事実の硬さは中身で守り、語りは砕けたまま保つ)"
fi

if [ -z "$violations" ] && [ -z "$menu" ] && [ -z "$evasion" ] && [ -z "$tone" ]; then
  printf '{}\n'
  exit 0
fi

reason=""
[ -z "$violations" ] || reason="初出で定義していない語:${violations}(平易な日本語に置き換えるか、初出で「語(説明)」の形で定義する)"
[ -z "$menu" ] || reason="${reason}${reason:+ / }判断を投げ返す言い回し: ${menu}(選択肢を並べず、自分の判断で進めて結果を報告する)"
[ -z "$evasion" ] || reason="${reason}${reason:+ / }${evasion}"
[ -z "$tone" ] || reason="${reason}${reason:+ / }${tone}"
jq -n --arg reason "$reason" \
  '{decision:"block", reason:("応答スタイル違反: " + $reason + "\n書き換えて応答し直せ。")}'
