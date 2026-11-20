#!/usr/bin/env bash
# SessionStart hook: Herdr の内側と外側で、対応する skill の選択条件を伝える。
# skill の発動はモデルが description に気づくかに依存するため、確定的に注入する。
set -u

if [ -z "${HC_TERMINAL_ID:-}" ]; then
  cat <<'EOF'
<herdr-context>
このセッションは herdr-core の端末の外で動いています。Herdr Core を利用する明示的な依頼がある場合に herdr-core skill を選んでください。通常の長いコマンドやバックグラウンド作業は既存の実行ツールで進めます。公式 skill の用途に該当することだけを理由に、hc の利用確認を挟みません。
</herdr-context>
EOF
fi

if [ -n "${HC_TERMINAL_ID:-}" ]; then
  cat <<'EOF'
<herdr-context>
このセッションは herdr-core の端末の中で動いている (HC_TERMINAL_ID が設定されている)。
既存の Core 端末を操作する仕事や、継続観測・途中のやり取りが必要な仕事には、依頼に Herdr の名前がなくても hc を選んでください。短いローカル操作は直接実行してください。
hc を使う前に herdr-core skill を開き、操作手順を確認してください。手段選択と子の確認待ちへの対応は、この起動時の案内を優先してください。
子が blocked を報告したら、画面を読んで質問と権限確認を見分けてください。委任された作業上の質問は、選択肢を確かめて hc keys で答えてください。権限確認は対象操作を照合して不足する承認を取得してください。
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
