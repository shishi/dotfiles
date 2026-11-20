#!/usr/bin/env bash
# SessionStart hook: Codex の組み込みの Auto-review の方針に利用者の規則を足した [auto_review].policy を、
# Codex の更新で組み込みの方針が変わっていれば書き直す (agent-shared/bin/apply-action-policy --codex)。
# Codex は起動時に設定を読み終えているので、書き直した内容は次のセッションで読み込まれる。
# fail-open: 標準出力はモデルへの文脈になるため何も出さず、失敗しても理由を標準エラーに 1 行出して正常終了する。
set -u

# 生成器は tomllib (Python 3.11 以降) を使う。macOS の /usr/bin/python3 のように古いものや、Windows の
# Microsoft Store の別名のように起動できないものを飛ばす。
for py_bin in python3 python; do
  command -v "$py_bin" >/dev/null 2>&1 && "$py_bin" -c 'import tomllib' >/dev/null 2>&1 || continue
  err=$("$py_bin" "$HOME/.agent-shared/bin/apply-action-policy" --codex 2>&1 >/dev/null) ||
    echo "codex-review-policy: Auto-review の方針を更新できませんでした: $(printf '%s\n' "$err" | tail -n 1)" >&2
  exit 0
done
echo 'codex-review-policy: tomllib を使える Python (3.11 以降) が見つからないため、Auto-review の方針を更新できませんでした。' >&2
exit 0
