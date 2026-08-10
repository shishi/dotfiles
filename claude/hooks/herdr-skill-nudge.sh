#!/usr/bin/env bash
# SessionStart hook: herdr 内 (HERDR_ENV=1) のセッションで herdr skill の使用を促す。
# skill の発動はモデルが description に気づくかに依存するため、確定的に注入する。
# fail-open: herdr 外では何も出力せず正常終了する。
set -u

if [ "${HERDR_ENV:-}" = "1" ]; then
  cat <<'EOF'
<herdr-context>
このセッションは herdr の内側で動いている (HERDR_ENV=1)。
タブを開く・ペインを分割する・エージェントを起動する・他ペインの出力を読む・状態を待つ、
など herdr の操作を頼まれたら、必ず先に herdr skill を invoke してから CLI を使うこと。
</herdr-context>
EOF
fi
exit 0
