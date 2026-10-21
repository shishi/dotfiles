#!/usr/bin/env bash
set -eu

payload=$(cat)
if ! printf '%s\n' "$payload" | jq -e 'type == "object" and .hook_event_name == "Stop" and (.stop_hook_active | type == "boolean")' >/dev/null 2>&1; then
  echo 'task-completion: expected a Stop event with boolean stop_hook_active' >&2
  exit 1
fi

# 両 CLI の stop_hook_active で、検査による継続が検査自身を再起動する循環を防ぐ。
if printf '%s\n' "$payload" | jq -e '.stop_hook_active' >/dev/null; then
  printf '{}\n'
  exit 0
fi

reason=$(cat <<'TEXT'
終了前の未達検査。現在の会話で有効なユーザーの元の依頼・訂正・全対象・維持条件を、実物と直接の検証結果に照合する。報告文の表現や計画の完了表示だけで判断しない。
承認済みで実行できる残作業があれば、最終回答で終了せず、修正・検証・反映・後片付けまで続ける。一部経路の失敗や途中の成功を全体の終了理由にしない。同じ失敗経路の再試行停止と、目標全体の停止を区別し、安全な別経路と依存しない残作業も確認する。
ユーザーの明示的な中止・一時停止、説明のみ・変更禁止・承認待ち、会話の境界、上位指示と権限制約は維持する。この検査は新しい作業や権限を与えない。完了、明示的な停止、または利用可能な安全な経路と独立した作業を調べても続行不能と確認できた場合は終了できる。続行不能なら試した経路と結果・残件・再開条件を示す。
この照合は同じ会話の担当が行う。検査のためだけの報告や再承認を増やさず、既に取得した証拠を使い、不足する確認と作業だけ実行する。要求された最終報告には実際の成果と未確認事項を正確に含める。
TEXT
)
jq -n --arg reason "$reason" '{decision:"block",reason:$reason}'
