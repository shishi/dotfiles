#!/usr/bin/env bash
# SessionStart hook: herdr-core の端末 (HC_TERMINAL_ID) の中の各 agent に、対応する skill の使用を促す。
# fail-open: herdr-core の外では何も出力せず正常終了する。
set -u

if [ -n "${HC_TERMINAL_ID:-}" ]; then
  cat <<'EOF'
<herdr-context>
このセッションは herdr-core の端末の中で動いています (HC_TERMINAL_ID が設定されています)。
委譲を決める前に agent-delegation を読み、独立した仕事は Core の子端末を優先してください。
端末の操作・実行・観測は herdr-core、利用者に見せる画面の操作は herdr-app の手順を使ってください。
</herdr-context>
EOF
fi
exit 0
