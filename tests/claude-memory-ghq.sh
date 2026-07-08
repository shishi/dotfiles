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

# --- 7: 正規 clone は mv で移行される (親ディレクトリ作成込みは 14 で検証) ---
begin
make_clone "$HOME/dev/claude-memory" "$CANON_URL"
mkdir -p "$TMP/ghq/github.com/shishi"
new="$TMP/ghq/github.com/shishi/claude-memory"
out="$(GHQ_ROOT="$TMP/ghq" bash "$HELPER" 2>/dev/null)"
[ "$out" = "$new" ] && [ -d "$new/.git" ] && [ ! -e "$HOME/dev/claude-memory" ] \
  && ok "7: canonical clone migrated to ghq path" \
  || ng "7: out=$out new-git=$([ -d "$new/.git" ] && echo y || echo n)"
end

# --- 8: clone でない/origin 不一致は移行しない (near-match も拒否) ---
begin
mkdir -p "$HOME/dev/claude-memory"   # .git なし
out="$(GHQ_ROOT="$TMP/ghq" bash "$HELPER" 2>/dev/null)"
[ "$out" = "$HOME/dev/claude-memory" ] && [ ! -e "$TMP/ghq/github.com/shishi/claude-memory" ] \
  && ok "8a: non-repo dir not migrated" || ng "8a: out=$out"
end
for bad_url in \
  "git@github.com:notshishi/claude-memory.git" \
  "https://github.com/shishi/claude-memory-fork"; do
  begin
  make_clone "$HOME/dev/claude-memory" "$bad_url"
  out="$(GHQ_ROOT="$TMP/ghq" bash "$HELPER" 2>/dev/null)"
  [ "$out" = "$HOME/dev/claude-memory" ] && [ -d "$HOME/dev/claude-memory/.git" ] \
    && ok "8b: near-match origin rejected ($bad_url)" \
    || ng "8b: out=$out ($bad_url)"
  end
done

# --- 8c: 明示 override 時は旧 clone があっても移行しない ---
begin
make_clone "$HOME/dev/claude-memory" "$CANON_URL"
out="$(CLAUDE_MEMORY_DIR="$TMP/somewhere" bash "$HELPER" 2>/dev/null)"
[ "$out" = "$TMP/somewhere" ] && [ -d "$HOME/dev/claude-memory/.git" ] \
  && ok "8c: explicit override never migrates" || ng "8c: out=$out"
end

# --- 9: claude/memory が実体ディレクトリなら移行しない ---
begin
make_clone "$HOME/dev/claude-memory" "$CANON_URL"
mkdir -p "$DOTDIR/claude/memory"   # symlink ではなく実体
out="$(GHQ_ROOT="$TMP/ghq" bash "$HELPER" 2>/dev/null)"
[ "$out" = "$HOME/dev/claude-memory" ] && [ ! -e "$TMP/ghq/github.com/shishi/claude-memory" ] \
  && ok "9: real claude/memory dir blocks migration" || ng "9: out=$out"
end

# --- 10-12: 旧・新両方存在時の判定 ---
begin
make_clone "$HOME/dev/claude-memory" "$CANON_URL"
new="$TMP/ghq/github.com/shishi/claude-memory"
make_clone "$new" "$CANON_URL"
ln -s "$HOME/dev/claude-memory" "$DOTDIR/claude/memory"
out="$(GHQ_ROOT="$TMP/ghq" bash "$HELPER" 2>/dev/null)"
[ "$out" = "$HOME/dev/claude-memory" ] \
  && ok "10: both exist, symlink->old keeps old" || ng "10: out=$out"
end
begin
make_clone "$HOME/dev/claude-memory" "$CANON_URL"
new="$TMP/ghq/github.com/shishi/claude-memory"
make_clone "$new" "$CANON_URL"
ln -s "$new" "$DOTDIR/claude/memory"
out="$(GHQ_ROOT="$TMP/ghq" bash "$HELPER" 2>/dev/null)"
[ "$out" = "$new" ] \
  && ok "11: both exist, symlink->new keeps new" || ng "11: out=$out"
end
begin
make_clone "$HOME/dev/claude-memory" "$CANON_URL"
new="$TMP/ghq/github.com/shishi/claude-memory"
make_clone "$new" "$CANON_URL"
out="$(GHQ_ROOT="$TMP/ghq" bash "$HELPER" 2>/dev/null)"
[ "$out" = "$HOME/dev/claude-memory" ] \
  && ok "12: both exist, undecidable keeps old" || ng "12: out=$out"
end

# --- 13: DOTDIR 未設定なら移行しない (fail closed) ---
begin
make_clone "$HOME/dev/claude-memory" "$CANON_URL"
out="$(unset DOTDIR; GHQ_ROOT="$TMP/ghq" bash "$HELPER" 2>/dev/null)"
[ "$out" = "$HOME/dev/claude-memory" ] && [ ! -e "$TMP/ghq/github.com/shishi/claude-memory" ] \
  && ok "13: unset DOTDIR blocks migration" || ng "13: out=$out"
end

# --- 14: 新パスの親ごと未存在でもヘルパーが mkdir -p して移行完遂 ---
begin
make_clone "$HOME/dev/claude-memory" "$CANON_URL"
new="$TMP/ghq/github.com/shishi/claude-memory"   # $TMP/ghq 自体を作らない
out="$(GHQ_ROOT="$TMP/ghq" bash "$HELPER" 2>/dev/null)"
[ "$out" = "$new" ] && [ -d "$new/.git" ] && [ ! -e "$HOME/dev/claude-memory" ] \
  && ok "14: helper creates parent dirs before mv" || ng "14: out=$out"
end

# --- 14b/14c: 新パスが regular file / broken symlink なら移行しない ---
begin
make_clone "$HOME/dev/claude-memory" "$CANON_URL"
new="$TMP/ghq/github.com/shishi/claude-memory"
mkdir -p "$(dirname "$new")"; : > "$new"   # regular file
out="$(GHQ_ROOT="$TMP/ghq" bash "$HELPER" 2>/dev/null)"
[ "$out" = "$HOME/dev/claude-memory" ] && [ -f "$new" ] && [ -d "$HOME/dev/claude-memory/.git" ] \
  && ok "14b: regular file at new path blocks migration" || ng "14b: out=$out"
end
begin
make_clone "$HOME/dev/claude-memory" "$CANON_URL"
new="$TMP/ghq/github.com/shishi/claude-memory"
mkdir -p "$(dirname "$new")"; ln -s "$TMP/nowhere" "$new"   # broken symlink
out="$(GHQ_ROOT="$TMP/ghq" bash "$HELPER" 2>/dev/null)"
[ "$out" = "$HOME/dev/claude-memory" ] && [ -L "$new" ] && [ -d "$HOME/dev/claude-memory/.git" ] \
  && ok "14c: broken symlink at new path blocks migration" || ng "14c: out=$out"
end

# --- 15: 警告が出るケースでも stdout はパス 1 行のみ ---
begin
make_clone "$HOME/dev/claude-memory" "$CANON_URL"
make_clone "$TMP/ghq/github.com/shishi/claude-memory" "$CANON_URL"   # 両方存在 → 警告
lines="$(GHQ_ROOT="$TMP/ghq" bash "$HELPER" 2>/dev/null | wc -l | tr -d ' ')"
[ "$lines" = "1" ] && ok "15: stdout is exactly one line" || ng "15: lines=$lines"
end

# --- setup.sh: gitconfig symlink が claude-memory 処理より前にあること ---
gitconfig_line="$(grep -n '\.gitconfig\.mac' "$SETUP" | head -n1 | cut -d: -f1)"
memory_line="$(grep -n 'resolve-memory-dir\.sh' "$SETUP" | head -n1 | cut -d: -f1)"
if [ -n "$gitconfig_line" ] && [ -n "$memory_line" ] && [ "$gitconfig_line" -lt "$memory_line" ]; then
  ok "setup.sh links gitconfig before resolving claude-memory"
else
  ng "setup.sh: gitconfig at line ${gitconfig_line:-none}, memory resolve at line ${memory_line:-none}"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
