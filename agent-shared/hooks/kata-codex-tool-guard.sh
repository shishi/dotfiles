#!/usr/bin/env bash
set -u

payload=$(jq -ce '. as $event | {session_id,turn_id,tool_name}
  | select(all(.[]; type == "string" and length > 0))
  | .agent_id = $event.agent_id') || {
  echo "調査結果を照合するための操作情報が取得できませんでした。" >&2
  exit 2
}
if ! curl --silent --fail --noproxy '*' --max-time 8 --unix-socket "$KATA_RESEARCH_CHECK_SOCKET" \
  --header 'Content-Type: application/json' --data-binary "$payload" --output /dev/null http://localhost/check; then
  echo "調査結果または独立した許可を確認できなかったため、この操作を止めました。" >&2
  exit 2
fi
