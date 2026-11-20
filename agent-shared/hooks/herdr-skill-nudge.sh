#!/usr/bin/env bash
# SessionStart hook: herdr-core の端末 (HC_TERMINAL_ID) や旧 herdr (HERDR_ENV=1) の中の各 agent に、対応する skill の使用を促す。
# skill の発動はモデルが description に気づくかに依存するため、確定的に注入する。
# fail-open: どちらの外でも何も出力せず正常終了する。
set -u

if [ -n "${HC_TERMINAL_ID:-}" ]; then
  cat <<'EOF'
<herdr-context>
このセッションは herdr-core の端末の中で動いている (HC_TERMINAL_ID が設定されている)。
Herdr の名前が依頼に出ていなくても、端末や子エージェントの継続実行・観測が作業に合うときは、
herdr-core skill を開いて手段を選んでください。hc を使う前には必ず同 skill を開いてください。
Herdr のデスクトップ画面の表示や配置を変えるときは herdr-app skill を使ってください。
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
