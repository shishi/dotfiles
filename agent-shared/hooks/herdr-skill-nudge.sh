#!/usr/bin/env bash
# SessionStart hook: herdr-core の端末 (HC_TERMINAL_ID) や旧 herdr (HERDR_ENV=1) の中の各 agent に、対応する skill の使用を促す。
# skill の発動はモデルが description に気づくかに依存するため、確定的に注入する。
# fail-open: どちらの外でも何も出力せず正常終了する。
set -u

if [ -n "${HC_TERMINAL_ID:-}" ]; then
  cat <<'EOF'
<herdr-context>
このセッションは herdr-core の端末の中で動いている (HC_TERMINAL_ID が設定されている)。
hc・herdr-core・Herdr の端末やエージェントの操作 (起動・出力の読み取り・話しかける・待つ) を頼まれたら、
必ず先に herdr-core skill を invoke してから hc を使うこと。Herdr のデスクトップ画面の表示や配置を
変えるときは herdr-app skill を使うこと。
</herdr-context>
EOF
elif [ "${HERDR_ENV:-}" = "1" ]; then
  cat <<'EOF'
<herdr-context>
このセッションは herdr の内側で動いている (HERDR_ENV=1)。
タブを開く・ペインを分割する・エージェントを起動する・他ペインの出力を読む・状態を待つ、
など herdr の操作を頼まれたら、必ず先に herdr skill を invoke してから CLI を使うこと。
</herdr-context>
EOF
fi
exit 0
