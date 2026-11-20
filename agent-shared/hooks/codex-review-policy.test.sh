#!/usr/bin/env bash
# codex-review-policy.sh が、Codex の組み込みの方針の変化に合わせて config.toml の [auto_review].policy を
# 書き直し、変化が無いときや方針を取れないときは何も書かず黙って終わることを、偽の codex で確かめる。
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
  "$tmp/home/.agent-shared" "$tmp/fakebin"
cp "$repo/agent-shared/bin/apply-action-policy" "$work/agent-shared/bin/"
cp "$here/codex-review-policy.sh" "$work/agent-shared/hooks/" 2>/dev/null
ln -s "$work/agent-shared/bin" "$tmp/home/.agent-shared/bin"
cat >"$work/agent-shared/policy/action-policy.json" <<'EOF'
{"drop_default_allow": [], "rules": [
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

cp "$work/codex/config.toml" "$tmp/config.before"
run_hook "$tmp/missing.json"; rc=$?
if [ "$rc" -eq 0 ] && cmp -s "$tmp/config.before" "$work/codex/config.toml" && [ ! -s "$tmp/stdout" ]; then
  ok "方針を取れなければ何も書かず正常終了する"
else
  ng "方針を取れなければ何も書かず正常終了する (rc=$rc)"
fi

exit "$fail"
