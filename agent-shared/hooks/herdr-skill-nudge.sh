#!/usr/bin/env bash
# SessionStart hook: herdr-core の端末 (HC_TERMINAL_ID) の中の各 agent に、対応する skill の使用を促す。
# skill の発動はモデルが description に気づくかに依存するため、確定的に注入する。
# 選択条件は agent-shared/skill-overlays/herdr-core.md の description と同じ内容に保つ。
# fail-open: herdr-core の外では何も出力せず正常終了する。
set -u

if [ -n "${HC_TERMINAL_ID:-}" ]; then
  cat <<'EOF'
<herdr-context>
このセッションは herdr-core の端末の中で動いています (HC_TERMINAL_ID が設定されています)。
既存の Core 端末を操作する仕事や、継続観測・途中のやり取りが必要な仕事には、依頼に Herdr の名前がなくても hc を選んでください。短いローカル操作は直接実行してください。
hc を使う前に herdr-core skill を開き、冒頭の補足と操作手順を確認してください。
Herdr のデスクトップ画面の表示や配置を変えるときは herdr-app skill を使ってください。
</herdr-context>
EOF
fi
exit 0
