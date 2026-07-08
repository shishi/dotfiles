#!/usr/bin/env bash
# claude/resolve-memory-dir.sh のスモークテスト。
# 使い方: bash tests/claude-memory-ghq.sh
# HOME / GIT_CONFIG_GLOBAL / DOTDIR を一時ディレクトリへ向けるので実環境は触らない。
# spec: docs/superpowers/specs/2026-07-07-claude-memory-ghq-design.md
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
  export HOME="$TMP/home"; mkdir -p "$HOME"
  export GIT_CONFIG_GLOBAL="$TMP/gitconfig"; : > "$GIT_CONFIG_GLOBAL"
  export GIT_CONFIG_SYSTEM=/dev/null
  export DOTDIR="$TMP/dotfiles"; mkdir -p "$DOTDIR/claude"
  unset GHQ_ROOT CLAUDE_MEMORY_DIR || true
  export PATH="$ORIG_PATH"
}
end() { rm -rf "$TMP"; }

CANON_URL="git@github.com:shishi/claude-memory.git"
make_clone() { # make_clone <dir> <origin-url>
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" remote add origin "$2"
}

# --- 1: CLAUDE_MEMORY_DIR 明示指定は絶対化されて最優先で返る ---
begin
out="$(CLAUDE_MEMORY_DIR="$TMP/explicit" bash "$HELPER")"
[ "$out" = "$TMP/explicit" ] && ok "1a: explicit absolute path returned as-is" \
  || ng "1a: expected $TMP/explicit, got $out"
out="$(CLAUDE_MEMORY_DIR="~/mem" bash "$HELPER")"
[ "$out" = "$HOME/mem" ] && ok "1b: leading ~/ expanded to \$HOME" \
  || ng "1b: expected $HOME/mem, got $out"
out="$(cd "$TMP" && CLAUDE_MEMORY_DIR="rel/mem" bash "$HELPER")"
[ "$out" = "$TMP/rel/mem" ] && ok "1c: relative path absolutized against cwd" \
  || ng "1c: expected $TMP/rel/mem, got $out"
end

# --- 2: 空文字は未指定扱いで ghq 解決に進む ---
begin
out="$(CLAUDE_MEMORY_DIR="" GHQ_ROOT="$TMP/ghq" bash "$HELPER")"
[ "$out" = "$TMP/ghq/github.com/shishi/claude-memory" ] \
  && ok "2: empty CLAUDE_MEMORY_DIR falls through to ghq" \
  || ng "2: got $out"
end

# --- 3: GHQ_ROOT のチルダは展開される ---
begin
out="$(GHQ_ROOT="~/xxx" bash "$HELPER")"
[ "$out" = "$HOME/xxx/github.com/shishi/claude-memory" ] \
  && ok "3: GHQ_ROOT tilde expanded" || ng "3: got $out"
end

# --- 4: GHQ_ROOT なしなら gitconfig の ghq.root ---
begin
printf '[ghq]\n\troot = ~/yyy\n' > "$GIT_CONFIG_GLOBAL"
out="$(bash "$HELPER")"
[ "$out" = "$HOME/yyy/github.com/shishi/claude-memory" ] \
  && ok "4: ghq.root from gitconfig" || ng "4: got $out"
end

# --- 5: ghq.root 複数値は先頭を採用 (ghq の primary root 仕様) ---
begin
printf '[ghq]\n\troot = ~/first\n\troot = ~/second\n' > "$GIT_CONFIG_GLOBAL"
out="$(bash "$HELPER")"
[ "$out" = "$HOME/first/github.com/shishi/claude-memory" ] \
  && ok "5: first ghq.root wins" || ng "5: got $out"
end

# --- 6: どちらもなければ従来デフォルト ---
begin
out="$(bash "$HELPER")"
[ "$out" = "$HOME/dev/claude-memory" ] \
  && ok "6: falls back to ~/dev/claude-memory" || ng "6: got $out"
end

# --- 4b: cwd の repo-local な ghq.root は無視される (--global のみ) ---
begin
mkdir -p "$TMP/localrepo"
git -C "$TMP/localrepo" init -q
git -C "$TMP/localrepo" config ghq.root "$TMP/evil"
out="$(cd "$TMP/localrepo" && bash "$HELPER")"
[ "$out" = "$HOME/dev/claude-memory" ] \
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
out="$(PATH="$TMP/bin:$PATH" CLAUDE_MEMORY_DIR="C:/tmp/memory" bash "$HELPER")"
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
[ "$out" = "/c/Users/test/dev/claude-memory" ] \
  && ok "6b: fallback normalized via cygpath" || ng "6b: got $out"
end

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
