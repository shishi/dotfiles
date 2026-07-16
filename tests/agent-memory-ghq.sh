#!/usr/bin/env bash
# claude/resolve-memory-dir.sh のスモークテスト。
# 使い方: bash tests/agent-memory-ghq.sh
# HOME / GIT_CONFIG_GLOBAL / DOTDIR を一時ディレクトリへ向けるので実環境は触らない。
# ヘルパーは「配置先の解決」だけを行う (自動移行はしない。旧 claude-memory からの
# 移行は spec 手順で手動)。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO/claude/resolve-memory-dir.sh"
SETUP="$REPO/setup.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL+1)); echo "NG: $1"; }

ORIG_PATH="$PATH"
TMP=""
begin() {
  # mktemp の返すパスは symlink を含み得るので物理パスに正規化しておく
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  [ -n "$TMP" ] || { echo "fatal: mktemp failed" >&2; exit 1; }
  export HOME="$TMP/home"; mkdir -p "$HOME"
  export GIT_CONFIG_GLOBAL="$TMP/gitconfig"; : > "$GIT_CONFIG_GLOBAL"
  export GIT_CONFIG_SYSTEM=/dev/null
  export DOTDIR="$TMP/dotfiles"; mkdir -p "$DOTDIR/claude"
  unset GHQ_ROOT AGENT_MEMORY_DIR || true
  export PATH="$ORIG_PATH"
}
end() { rm -rf "$TMP"; }

REPO_REL="github.com/shishi/agent-memory"
# 無 ghq 時のフォールバック root (origin/master のハードコード既定と一致)
DEFAULT_REL="dev/src/$REPO_REL"

# --- 1: AGENT_MEMORY_DIR 明示指定は絶対化されて最優先で返る ---
begin
out="$(AGENT_MEMORY_DIR="$TMP/explicit" bash "$HELPER")"
[ "$out" = "$TMP/explicit" ] && ok "1a: explicit absolute path returned as-is" \
  || ng "1a: expected $TMP/explicit, got $out"
out="$(AGENT_MEMORY_DIR="~/mem" bash "$HELPER")"
[ "$out" = "$HOME/mem" ] && ok "1b: leading ~/ expanded to \$HOME" \
  || ng "1b: expected $HOME/mem, got $out"
out="$(cd "$TMP" && AGENT_MEMORY_DIR="rel/mem" bash "$HELPER")"
[ "$out" = "$TMP/rel/mem" ] && ok "1c: relative path absolutized against cwd" \
  || ng "1c: expected $TMP/rel/mem, got $out"
end

# --- 2: 空文字は未指定扱いで ghq 解決に進む ---
begin
out="$(AGENT_MEMORY_DIR="" GHQ_ROOT="$TMP/ghq" bash "$HELPER")"
[ "$out" = "$TMP/ghq/$REPO_REL" ] \
  && ok "2: empty AGENT_MEMORY_DIR falls through to ghq" \
  || ng "2: got $out"
end

# --- 3: GHQ_ROOT のチルダは展開される ---
begin
out="$(GHQ_ROOT="~/xxx" bash "$HELPER")"
[ "$out" = "$HOME/xxx/$REPO_REL" ] \
  && ok "3: GHQ_ROOT tilde expanded" || ng "3: got $out"
end

# --- 4: GHQ_ROOT なしなら gitconfig の ghq.root ---
begin
printf '[ghq]\n\troot = ~/yyy\n' > "$GIT_CONFIG_GLOBAL"
out="$(bash "$HELPER")"
[ "$out" = "$HOME/yyy/$REPO_REL" ] \
  && ok "4: ghq.root from gitconfig" || ng "4: got $out"
end

# --- 5: ghq.root 複数値は先頭を採用 (ghq の primary root 仕様) ---
begin
printf '[ghq]\n\troot = ~/first\n\troot = ~/second\n' > "$GIT_CONFIG_GLOBAL"
out="$(bash "$HELPER")"
[ "$out" = "$HOME/first/$REPO_REL" ] \
  && ok "5: first ghq.root wins" || ng "5: got $out"
end

# --- 6: どちらもなければ既定 ghq root (~/dev/src) 配下 ---
begin
out="$(bash "$HELPER")"
[ "$out" = "$HOME/$DEFAULT_REL" ] \
  && ok "6: falls back to ~/$DEFAULT_REL" || ng "6: got $out"
end

# --- 4b: cwd の repo-local な ghq.root は無視される (--global のみ) ---
begin
mkdir -p "$TMP/localrepo"
git -C "$TMP/localrepo" init -q
git -C "$TMP/localrepo" config ghq.root "$TMP/evil"
out="$(cd "$TMP/localrepo" && bash "$HELPER")"
[ "$out" = "$HOME/$DEFAULT_REL" ] \
  && ok "4b: repo-local ghq.root ignored" || ng "4b: got $out"
end

# --- 16: drive-letter パスは cygpath で POSIX 形式へ正規化 ---
begin
mkdir -p "$TMP/bin"
cat > "$TMP/bin/cygpath" <<'EOF'
#!/bin/sh
# cygpath -u -a -- <path> の最低限の模擬: C:/foo -> /c/foo
p=""
for a in "$@"; do p="$a"; done
drive=$(printf '%s' "$p" | cut -c1 | tr '[:upper:]' '[:lower:]')
rest=$(printf '%s' "$p" | cut -c3-)
printf '/%s%s\n' "$drive" "$rest"
EOF
chmod +x "$TMP/bin/cygpath"
out="$(PATH="$TMP/bin:$PATH" AGENT_MEMORY_DIR="C:/tmp/memory" bash "$HELPER")"
[ "$out" = "/c/tmp/memory" ] \
  && ok "16: drive-letter normalized via cygpath" || ng "16: got $out"
end

# --- 6b: fallback 経路も POSIX 形式へ正規化される (Git Bash の HOME=C:/...) ---
begin
mkdir -p "$TMP/bin"
cat > "$TMP/bin/cygpath" <<'EOF'
#!/bin/sh
# cygpath -u -a -- <path> の最低限の模擬: C:/foo -> /c/foo
p=""
for a in "$@"; do p="$a"; done
drive=$(printf '%s' "$p" | cut -c1 | tr '[:upper:]' '[:lower:]')
rest=$(printf '%s' "$p" | cut -c3-)
printf '/%s%s\n' "$drive" "$rest"
EOF
chmod +x "$TMP/bin/cygpath"
out="$(PATH="$TMP/bin:$PATH" HOME="C:/Users/test" bash "$HELPER")"
[ "$out" = "/c/Users/test/$DEFAULT_REL" ] \
  && ok "6b: fallback normalized via cygpath" || ng "6b: got $out"
end

# --- 17: AGENT_MEMORY_DIR に改行が含まれる場合は拒否される ---
begin
out="$(AGENT_MEMORY_DIR=$'/tmp/a\nb' bash "$HELPER" 2>/dev/null)"
status=$?
[ "$status" -ne 0 ] && [ -z "$out" ] \
  && ok "17: newline in AGENT_MEMORY_DIR is rejected" \
  || ng "17: expected exit!=0 and empty stdout, got status=$status out=$(printf '%s' "$out" | head -c 40)"
end

# --- 18: GHQ_ROOT に末尾スラッシュがある場合は正規化される ---
begin
out="$(GHQ_ROOT="$TMP/ghq/" bash "$HELPER")"
[ "$out" = "$TMP/ghq/$REPO_REL" ] \
  && ok "18: trailing slash on GHQ_ROOT is normalized" \
  || ng "18: expected $TMP/ghq/$REPO_REL, got $out"
end

# --- 19: 展開結果に改行が混入するケースも拒否される (HOME 由来) ---
begin
out="$(HOME=$'/tmp/h\n' AGENT_MEMORY_DIR='~' bash "$HELPER" 2>/dev/null)"
status=$?
[ "$status" -ne 0 ] && [ -z "$out" ] \
  && ok "19: newline from expansion rejected" || ng "19: status=$status out=$out"
end

# --- setup.sh: gitconfig symlink が memory 処理より前にあること ---
gitconfig_line="$(grep -n '\.gitconfig\.mac' "$SETUP" | head -n1 | cut -d: -f1)"
memory_line="$(grep -n 'resolve-memory-dir\.sh' "$SETUP" | head -n1 | cut -d: -f1)"
if [ -n "$gitconfig_line" ] && [ -n "$memory_line" ] && [ "$gitconfig_line" -lt "$memory_line" ]; then
  ok "setup.sh links gitconfig before resolving memory dir"
else
  ng "setup.sh: gitconfig at line ${gitconfig_line:-none}, memory resolve at line ${memory_line:-none}"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
