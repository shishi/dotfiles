#!/usr/bin/env bash
# codex-review-policy.sh が、独自ポリシーの有効・無効に応じて config.toml を更新することを確かめる。
# 使い方: bash agent-shared/hooks/codex-review-policy.test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/codex-review-policy-test.XXXXXX") || exit 1
tmp=$(cd -P "$tmp" && pwd) || exit 1
trap 'rm -rf "$tmp"' EXIT
fail=0

ok() { echo "ok   $1"; }
ng() { echo "FAIL $1"; fail=1; }

work="$tmp/dotfiles"
mkdir -p "$work/agent-shared/bin" "$work/agent-shared/hooks" "$work/agent-shared/policy" "$work/codex" \
  "$work/claude" "$tmp/home/.agent-shared" "$tmp/fakebin"
cp "$repo/agent-shared/bin/apply-action-policy" "$work/agent-shared/bin/"
cp "$here/codex-review-policy.sh" "$work/agent-shared/hooks/" 2>/dev/null
cp "$here/permission-judge.sh" "$work/agent-shared/hooks/"
ln -s "$work/agent-shared/bin" "$tmp/home/.agent-shared/bin"
cat >"$work/agent-shared/policy/action-policy.json" <<'EOF'
{"enabled": true, "codex_custom_policy": true, "drop_default_allow": [], "rules": [
  {"section": "environment", "text": "Env A"},
  {"section": "soft_deny", "text": "Block A"},
  {"section": "allow", "text": "Allow A"}
]}
EOF
cat >"$work/codex/config.toml" <<'EOF'
model_reasoning_effort = "high"

[auto_review]
policy = '''
OLD BUILTIN

# User-specific rules
'''
timeout_ms = 120000

[agents]
enabled = true
EOF
cat >"$tmp/catalog.json" <<'EOF'
{"models": [
  {"slug": "codex-auto-review", "model_messages": {"auto_review": {"policy": "BUILTIN v2\n"}}},
  {"slug": "other", "model_messages": {"auto_review": null}}
]}
EOF
cat >"$tmp/fakebin/codex" <<'EOF'
#!/usr/bin/env bash
[ "$*" = "debug models" ] && [ -f "$FAKE_CATALOG" ] && exec cat "$FAKE_CATALOG"
exit 1
EOF
chmod +x "$tmp/fakebin/codex"

run_hook() {
  HOME="$tmp/home" PATH="$tmp/fakebin:$PATH" FAKE_CATALOG="$1" \
    bash "$work/agent-shared/hooks/codex-review-policy.sh" </dev/null >"$tmp/stdout" 2>"$tmp/stderr"
}
config_value() { # TOML のキーを点区切りで受け取り、末尾の改行も比べられるよう Python の repr で出す
  python3 -c 'import sys, tomllib
v = tomllib.load(open(sys.argv[1], "rb"))
for k in sys.argv[2].split("."): v = v[k]
print(repr(v), end="")' "$work/codex/config.toml" "$1"
}
mtime() { python3 -c 'import os, sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$work/codex/config.toml"; }

expected="'BUILTIN v2\\n\\n## User-specific rules\\n\\n### Environment\\n\\n- Env A\\n\\n### Block unless the user authorized this exact action\\n\\n- Block A\\n\\n### Allow\\n\\n- Allow A\\n'"

run_hook "$tmp/catalog.json"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(config_value auto_review.policy)" = "$expected" ]; then
  ok "古い組み込みの方針を新しい方針と規則で書き直す"
else
  ng "古い組み込みの方針を新しい方針と規則で書き直す (rc=$rc, stderr: $(cat "$tmp/stderr"))"
fi
[ "$(config_value agents.enabled)" = True ] && ok "ほかの表を残す" || ng "ほかの表を残す"
[ "$(config_value auto_review.timeout_ms)" = 120000 ] && ok "[auto_review] のほかのキーを残す" || ng "[auto_review] のほかのキーを残す"
[ ! -s "$tmp/stdout" ] && ok "書き直しても標準出力に何も出さない" || ng "書き直しても標準出力に何も出さない"

before=$(mtime)
run_hook "$tmp/catalog.json"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(mtime)" = "$before" ] && [ ! -s "$tmp/stdout" ]; then
  ok "方針が同じなら config.toml に書かない"
else
  ng "方針が同じなら config.toml に書かない (rc=$rc)"
fi

cp "$work/codex/config.toml" "$tmp/config.with-policy"
run_hook "$tmp/missing.json"; rc=$?
if [ "$rc" -eq 0 ] && cmp -s "$tmp/config.with-policy" "$work/codex/config.toml" && [ ! -s "$tmp/stdout" ]; then
  ok "方針を取れなければ何も書かず正常終了する"
else
  ng "方針を取れなければ何も書かず正常終了する (rc=$rc)"
fi

python3 - "$work/agent-shared/policy/action-policy.json" "$work/codex/config.toml" <<'PY'
import json, pathlib, sys

path = pathlib.Path(sys.argv[1])
policy = json.loads(path.read_text())
policy["codex_custom_policy"] = False
path.write_text(json.dumps(policy))

config = pathlib.Path(sys.argv[2])
config.write_text(config.read_text().replace("[auto_review]", "[auto_review] # Local review settings"))
PY
cp "$work/codex/config.toml" "$tmp/config.with-policy"
run_hook "$tmp/missing.json"
if python3 - "$work/codex/config.toml" <<'PY'
import pathlib, sys, tomllib

path = pathlib.Path(sys.argv[1])
assert tomllib.loads(path.read_text()) == {
    "model_reasoning_effort": "high",
    "auto_review": {"timeout_ms": 120000},
    "agents": {"enabled": True},
}
PY
then
  ok "無効なら独自ポリシーだけを外す"
else
  ng "無効なら独自ポリシーだけを外す"
fi

before=$(mtime)
run_hook "$tmp/catalog.json"
if [ "$(mtime)" = "$before" ] && [ ! -s "$tmp/stdout" ] && [ ! -s "$tmp/stderr" ]; then
  ok "次の起動でも独自ポリシーを再適用しない"
else
  ng "次の起動でも独自ポリシーを再適用しない"
fi

python3 - "$work/agent-shared/policy/action-policy.json" <<'PY'
import json, pathlib, sys

path = pathlib.Path(sys.argv[1])
policy = json.loads(path.read_text())
policy.update(enabled=False, codex_custom_policy=True)
path.write_text(json.dumps(policy))
PY
cp "$work/codex/config.toml" "$tmp/config.before"
run_hook "$tmp/catalog.json"
if cmp -s "$tmp/config.before" "$work/codex/config.toml" && [ ! -s "$tmp/stderr" ]; then
  ok "一時停止中は Codex の起動時に適用しない"
else
  ng "一時停止中は Codex の起動時に適用しない"
fi

cat >"$tmp/fakebin/claude" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$tmp/fakebin/claude"
if PATH="$tmp/fakebin:$PATH" bash "$work/agent-shared/hooks/permission-judge.sh" >"$tmp/decision" <<'EOF' && [ ! -s "$tmp/decision" ]; then
{"tool_name":"Bash","tool_input":{"command":"true"}}
EOF
  ok "一時停止中は Claude Code の確認画面に代理で答えない"
else
  ng "一時停止中は Claude Code の確認画面に代理で答えない"
fi

printf '%s\n' '{"autoMode":{"allow":["Extra rule"]},"permissions":{"defaultMode":"auto"}}' >"$work/claude/settings.json"
cp "$tmp/config.with-policy" "$work/codex/config.toml"
if PATH="$tmp/fakebin:$PATH" FAKE_CATALOG="$tmp/catalog.json" python3 "$work/agent-shared/bin/apply-action-policy" && \
    python3 -c 'import json, sys; assert json.load(open(sys.argv[1])) == {"permissions": {"defaultMode": "auto"}}' "$work/claude/settings.json" && \
    cmp -s "$tmp/config.before" "$work/codex/config.toml"; then
  ok "一時停止中の手動適用で両 CLI が組み込みポリシーに戻る"
else
  ng "一時停止中の手動適用で両 CLI が組み込みポリシーに戻る"
fi

printf '%s\n' '{"enabled": true,' >"$work/agent-shared/policy/action-policy.json"
PATH="$tmp/fakebin:$PATH" bash "$work/agent-shared/hooks/permission-judge.sh" </dev/null >"$tmp/decision" 2>"$tmp/stderr"
if [ "$?" -ne 0 ] && [ ! -s "$tmp/decision" ]; then
  ok "設定を読めないときは Claude Code にフックの失敗を返す"
else
  ng "設定を読めないときは Claude Code にフックの失敗を返す"
fi

exit "$fail"
