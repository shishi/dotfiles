# claude-memory ghq 形式配置 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** setup.sh が claude-memory を ghq 規約パス(`<ghq_root>/github.com/shishi/claude-memory`)に配置し、旧デフォルト `~/dev/claude-memory` から安全に自動移行する。

**Architecture:** パス解決+移行を独立ヘルパー `claude/resolve-memory-dir.sh`(stdout に絶対パス 1 行、警告は stderr)に切り出し、setup.sh はその結果を検証して従来の clone/symlink 処理に渡すだけにする。ghq バイナリには依存しない。

**Tech Stack:** plain bash(bash 3.2 互換、macOS / Linux / Git Bash)、git CLI、既存の pass/fail 形式スモークテスト(`tests/`)。

**Spec:** `docs/superpowers/specs/2026-07-07-claude-memory-ghq-design.md`(必読。本プランはこの spec の実装)

## Global Constraints

- ヘルパーの exit contract: 成功 = exit 0 + stdout に **絶対パス 1 行のみ**。決定不能 = 非 0。警告はすべて stderr。
- 移行(mv)の安全条件(spec「既存 clone の移行」の 5 条件)をすべて満たす場合のみ mv。迷ったら「動いている旧パスを返す」に倒す(fail closed)。
- origin URL 照合は anchored 完全一致のみ: `git@github.com:shishi/claude-memory(.git)?` / `ssh://git@github.com/shishi/claude-memory(.git)?` / `https://github.com/shishi/claude-memory(.git)?`
- `CLAUDE_MEMORY_DIR` 明示指定時は移行しない。未設定と空文字は「未指定」扱い。
- 削除(`rm`)や上書きは一切しない。既存データを壊す操作は書かない。
- テストは実環境を触らない: `HOME` / `GIT_CONFIG_GLOBAL` / `DOTDIR` を一時ディレクトリへ向ける。
- コミットは Conventional Commits・WHY-focused body(git-commit skill)。structural change と behavioral change は別コミット(Tidy First)。

---

### Task 1: ヘルパーのパス解決(explicit / ghq / fallback)

**Files:**
- Create: `claude/resolve-memory-dir.sh`
- Create: `tests/claude-memory-ghq.sh`
- Modify: `.gitignore`(`!/claude/install-plugins.sh` の直後に 1 行追加)

**Interfaces:**
- Produces: `bash claude/resolve-memory-dir.sh` — 環境変数 `CLAUDE_MEMORY_DIR` / `GHQ_ROOT` / `HOME` / `DOTDIR` / git global config を入力に、stdout へ解決済み絶対パスを 1 行出力(exit 0)。内部関数 `warn` / `absolutize` / `canon` は Task 2 も使う。
- Consumes: なし(先頭タスク)

- [ ] **Step 1: `.gitignore` にホワイトリスト行を追加**

`.gitignore` の `!/claude/install-plugins.sh` の直後に追加:

```
!/claude/resolve-memory-dir.sh
```

- [ ] **Step 2: 失敗するテストを書く**

`tests/claude-memory-ghq.sh` を新規作成(テスト 1〜6, 16 = パス解決のみ):

```bash
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
```

- [ ] **Step 3: テストを実行して失敗を確認**

Run: `bash tests/claude-memory-ghq.sh`
Expected: 全ケース NG(`claude/resolve-memory-dir.sh` が存在しないため)、exit 非 0

- [ ] **Step 4: ヘルパーを実装(パス解決のみ)**

`claude/resolve-memory-dir.sh` を新規作成:

```bash
#!/usr/bin/env bash
# claude-memory (個人永続記憶) の配置先を解決し、stdout に絶対パスを 1 行だけ出力する。
# ghq.root がある環境では <root>/github.com/shishi/claude-memory を使う。
# 旧デフォルト ~/dev/claude-memory からの自動移行 (mv) もここで行う。
# spec: docs/superpowers/specs/2026-07-07-claude-memory-ghq-design.md
#
# 入力はすべて環境変数:
#   CLAUDE_MEMORY_DIR  明示 override (最優先。移行はしない)
#   GHQ_ROOT           ghq root (gitconfig の ghq.root より優先)
#   DOTDIR             dotfiles リポジトリのパス (空なら移行しない = fail closed)
#   HOME / git global config
# exit contract: パスを決定できたら exit 0 + stdout 1 行。決定不能は非 0。警告は stderr。
set -u

REPO_PATH="github.com/shishi/claude-memory"

warn() { echo "resolve-memory-dir: $*" >&2; }

# 物理パスへ正規化 (symlink 比較用)。存在しないパスは空を返す。
canon() { (cd -P -- "$1" 2>/dev/null && pwd -P); }

# 先頭 ~/ を $HOME へ展開し、相対パスを絶対化する。
# Git Bash では C:/... のような drive-letter 形式が来るため、cygpath が
# あればそれで POSIX 形式 (/c/...) へ変換する (setup.sh 側の「/ 始まり」
# 検証を単純に保つため)。
absolutize() {
  local p="$1"
  case "$p" in
    "~") p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
  esac
  case "$p" in
    /*) ;;
    *)
      if command -v cygpath >/dev/null 2>&1; then
        p="$(cygpath -u -a -- "$p")" || return 1
      else
        p="$(pwd -P)/$p"
      fi
      ;;
  esac
  printf '%s\n' "$p"
}

# 1. 明示 override: 絶対化して返すだけ。移行はしない (devcontainer/CI の
#    一時パスへ記憶 repo を mv してしまう事故を防ぐ)。
if [ -n "${CLAUDE_MEMORY_DIR:-}" ]; then
  absolutize "$CLAUDE_MEMORY_DIR"
  exit $?
fi

# fallback も正規化する (Git Bash で HOME=C:/Users/... の場合に備え、
# stdout の「/ 始まり」契約を全経路で守る)
old="$(absolutize "$HOME/dev/claude-memory")" || exit 1

# 2. ghq root: GHQ_ROOT env → gitconfig ghq.root の先頭値 (ghq の primary root 仕様)。
#    --global 必須: 素の git config は cwd の repo-local config も読むため、
#    setup.sh の実行ディレクトリ次第で想定外の root を拾ってしまう。
ghq_root="${GHQ_ROOT:-}"
if [ -z "$ghq_root" ]; then
  ghq_root="$(git config --global --type=path --get-all ghq.root 2>/dev/null | head -n1 || true)"
fi

# 3. ghq root なし → 従来デフォルト
if [ -z "$ghq_root" ]; then
  printf '%s\n' "$old"
  exit 0
fi

ghq_root="$(absolutize "$ghq_root")" || exit 1
new="$ghq_root/$REPO_PATH"

if [ "$new" = "$old" ]; then
  printf '%s\n' "$new"
  exit 0
fi

# (移行ロジックは Task 2 で追加。現時点では新パスをそのまま返す)
printf '%s\n' "$new"
exit 0
```

- [ ] **Step 5: テストを実行して成功を確認**

Run: `bash tests/claude-memory-ghq.sh`
Expected: `ok:` × 11(1a/1b/1c/2/3/4/4b/5/6/6b/16)、`PASS=11 FAIL=0`、exit 0

- [ ] **Step 6: コミット**

```bash
git add .gitignore claude/resolve-memory-dir.sh tests/claude-memory-ghq.sh
git commit -m "feat(claude): resolve claude-memory dir via ghq.root convention

claude-memory の配置が ~/dev/claude-memory 固定で、ghq 管理下の他
リポジトリと規約が揃わなかった。GHQ_ROOT / gitconfig ghq.root がある
環境では <root>/github.com/shishi/claude-memory を返す独立ヘルパーを
追加する。ghq get には依存せずパス規約だけ借りる (認証フォールバックを
現状維持し、ghq 未導入環境でも同じコードパスで動かすため)。

明示 CLAUDE_MEMORY_DIR は絶対化して最優先で返し、相対パス・チルダ・
Git Bash の drive-letter 形式 (cygpath で POSIX 化) も正規化する。"
```

---

### Task 2: 旧パスからの安全な移行(mv)と両方存在時の判定

**Files:**
- Modify: `claude/resolve-memory-dir.sh`(末尾の「新パスをそのまま返す」部分を移行ロジックに置換)
- Modify: `tests/claude-memory-ghq.sh`(テスト 7〜15 を `echo` サマリの前に追加)

**Interfaces:**
- Consumes: Task 1 の `warn` / `canon` / `absolutize` / 変数 `old` / `new` / `REPO_PATH`
- Produces: ヘルパー最終形。exit contract は Global Constraints のとおり(setup.sh が Task 3 で依存)

- [ ] **Step 1: 失敗するテストを追加**

`tests/claude-memory-ghq.sh` の `echo`/`PASS=` サマリ行の**直前**に追加:

```bash
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
```

注意: spec のテスト 8b(明示 override は移行しない)は本ファイルでは `8c` のラベルにしている(8 の negative ループが `8b` を使うため)。内容は spec と同一。

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `bash tests/claude-memory-ghq.sh`
Expected: Task 1 の 9 ケースは ok のまま、7 / 9 / 13 / 14 は NG(移行ロジック未実装で新パスが返り、旧 clone が移動されないため)。8a/8b/8c/10/11/12/15 は実装前でも偶然通るものがあるが、7 と 14 が NG であることを必ず確認する。

- [ ] **Step 3: 移行ロジックを実装**

`claude/resolve-memory-dir.sh` の末尾ブロック:

```bash
# (移行ロジックは Task 2 で追加。現時点では新パスをそのまま返す)
printf '%s\n' "$new"
exit 0
```

を以下に置換:

```bash
# --- 旧デフォルトからの移行判定 ---
# 削除・上書きは一切しない。迷ったら「動いている旧パスを返す」に倒す。
link="${DOTDIR:+${DOTDIR}/claude/memory}"

# 旧パスが本物の claude-memory clone か (anchored 完全一致。緩い部分一致だと
# notshishi/claude-memory 等の near-match を誤って mv してしまう)
is_claude_memory_clone() {
  local dir="$1" url
  [ -d "$dir/.git" ] || return 1
  url="$(git -C "$dir" remote get-url origin 2>/dev/null)" || return 1
  case "$url" in
    "git@github.com:shishi/claude-memory" | "git@github.com:shishi/claude-memory.git" | \
    "ssh://git@github.com/shishi/claude-memory" | "ssh://git@github.com/shishi/claude-memory.git" | \
    "https://github.com/shishi/claude-memory" | "https://github.com/shishi/claude-memory.git")
      return 0 ;;
  esac
  return 1
}

if [ -d "$new" ]; then
  if [ -d "$old" ] && [ ! -L "$old" ]; then
    # 両方存在: 現に使われている側を維持する。symlink で判定できなければ
    # 旧を維持 (新が古い clone だと未 push の記憶が orphan になるため)。
    warn "both $old and $new exist; not touching either. resolve manually."
    if [ -n "$link" ] && [ -L "$link" ]; then
      cur="$(canon "$link")"
      if [ -n "$cur" ] && [ "$cur" = "$(canon "$new")" ]; then
        printf '%s\n' "$new"; exit 0
      fi
      if [ -n "$cur" ] && [ "$cur" = "$(canon "$old")" ]; then
        printf '%s\n' "$old"; exit 0
      fi
    fi
    printf '%s\n' "$old"
    exit 0
  fi
  printf '%s\n' "$new"
  exit 0
fi

# 新パス未存在・旧パスに実体なし → fresh clone 先として新パス
if [ ! -d "$old" ] || [ -L "$old" ]; then
  printf '%s\n' "$new"
  exit 0
fi

# 新パスが「ディレクトリ以外の何か」(regular file / broken symlink) の場合は
# mv の挙動が未定義に壊れる (上書き・symlink 先への移動等) ため移行しない
if [ -e "$new" ] || [ -L "$new" ]; then
  warn "$new exists but is not a usable directory; skip migration. fix manually."
  printf '%s\n' "$old"
  exit 0
fi

# 旧パスあり・新パス未存在: 安全条件をすべて満たす場合のみ mv 移行
if [ -z "${DOTDIR:-}" ]; then
  warn "DOTDIR not set; cannot verify claude/memory symlink. skip migration."
  printf '%s\n' "$old"
  exit 0
fi
if [ -e "$link" ] && [ ! -L "$link" ]; then
  warn "$link is a real directory (not a symlink); skip migration. fix manually."
  printf '%s\n' "$old"
  exit 0
fi
if ! is_claude_memory_clone "$old"; then
  warn "$old is not a clone of $REPO_PATH; skip migration."
  printf '%s\n' "$old"
  exit 0
fi
if ! mkdir -p "$(dirname "$new")"; then
  warn "cannot create $(dirname "$new"); skip migration."
  printf '%s\n' "$old"
  exit 0
fi
if mv "$old" "$new" 2>/dev/null && [ -d "$new/.git" ]; then
  warn "migrated $old -> $new"
  printf '%s\n' "$new"
  exit 0
fi
warn "migration $old -> $new failed"
if [ -d "$old" ]; then
  printf '%s\n' "$old"
  exit 0
fi
# 旧も新も使える状態でない → パス決定不能
exit 1
```

- [ ] **Step 4: テストを実行して成功を確認**

Run: `bash tests/claude-memory-ghq.sh`
Expected: `PASS=25 FAIL=0`(Task 1 の 11 + 本タスクの 14: 7/8a/8b×2/8c/9/10/11/12/13/14/14b/14c/15)、exit 0

- [ ] **Step 5: コミット**

```bash
git add claude/resolve-memory-dir.sh tests/claude-memory-ghq.sh
git commit -m "feat(claude): migrate legacy claude-memory clone to ghq path

旧デフォルト ~/dev/claude-memory に既存 clone がある環境が ghq 形式へ
移行されないと、環境ごとに配置が分裂したままになる。ヘルパー内で
安全条件 (ghq 由来の解決・origin の anchored 完全一致・claude/memory が
symlink・新パス未存在) をすべて満たす場合のみ mv する。

個人永続記憶は失うと復元できないため、判定に迷うケースはすべて
「動いている旧パスを返す」fail closed に倒し、削除・上書きは一切
行わない。両方存在時は現 symlink の指す先を維持し、判定不能なら
旧を維持する (新が古い clone だと未 push の記憶が orphan になるため)。"
```

---

### Task 3: setup.sh 統合と .gitconfig 順序修正

**Files:**
- Modify: `setup.sh`(gitconfig ブロック移動 + claude-memory セクション置換)
- Modify: `tests/claude-memory-ghq.sh`(順序検証を追加)

**Interfaces:**
- Consumes: Task 2 のヘルパー(`DOTDIR="$DOTDIR" bash "${DOTDIR}/claude/resolve-memory-dir.sh"` → stdout 絶対パス 1 行 / exit 0)
- Produces: なし(最終統合)

- [ ] **Step 1: 【structural】OS 別 gitconfig ブロックを claude-memory 処理より前へ移動**

`setup.sh` の以下のブロック(現行 145〜160 行付近、`if [ $(uname) = Darwin ]; then` から対応する `fi` まで):

```bash
if [ $(uname) = Darwin ]; then
  ln -sf ${DOTDIR}/.gitconfig.mac ~/.gitconfig
  ln -sf ${DOTDIR}/Brewfile ~/Brewfile
elif [ $(uname) = Linux ]; then
  ln -sf ${DOTDIR}/.gitconfig.linux ~/.gitconfig
  #    ln -sf ${DOTDIR}/terminator ${XDG_CONFIG_HOME}/terminator
  #    ln -sf ${DOTDIR}/.xprofile ~/.xprofile
  #    ln -sf ${DOTDIR}/.xbindkeysrc ~/.xbindkeysrc
  #    ln -sf ${DOTDIR}/.imwheelrc ~/.imwheelrc
  #    ln -sf ${DOTDIR}/imwheel.desktop ${XDG_CONFIG_HOME}/autostart/imwheel.desktop
  #    ln -sf ${DOTDIR}/fonts.conf ${XDG_CONFIG_HOME}/fontconfig/fonts.conf
  #    fc-cache -fv
elif [[ $(uname -s) == MINGW* ]]; then
  # uname はビルド番号付き (例: MINGW64_NT-10.0-26200) なのでパターンで判定する
  ln -sf ${DOTDIR}/.gitconfig.win ~/.gitconfig
fi
```

を元の場所から**削除**し、`# claude-memory (個人永続記憶, private repo) を ~/.claude/memory として参照させる。` コメント行の**直前**に、次の説明コメントを先頭に付けて**挿入**する:

```bash
# gitconfig は claude-memory 処理より前に張る。ヘルパーが git config の
# ghq.root を参照するため、後だと fresh 環境の初回実行だけ旧パスに
# clone される二段階挙動になってしまう。
```

- [ ] **Step 2: 移動だけで壊れていないことを確認**

Run: `bash -n setup.sh && bash tests/setup-windows-symlinks.sh`
Expected: syntax OK、既存テストが全部 ok(このテストは grep ベースなので移動の影響を受けない)

- [ ] **Step 3: 【structural】コミット**

```bash
git add setup.sh
git commit -m "refactor(setup): link OS gitconfig before claude-memory section

次コミットで claude-memory の配置解決が git config の ghq.root を
参照するようになる。gitconfig symlink が後だと fresh 環境の初回実行
だけ ghq.root が引けず旧パスへ clone される二段階挙動になるため、
参照より先に張る。ブロックの内容自体は無変更。"
```

- [ ] **Step 4: 順序検証テストを追加**

`tests/claude-memory-ghq.sh` のサマリ(`echo` / `PASS=` 行)の直前に追加:

```bash
# --- setup.sh: gitconfig symlink が claude-memory 処理より前にあること ---
gitconfig_line="$(grep -n '\.gitconfig\.mac' "$SETUP" | head -n1 | cut -d: -f1)"
memory_line="$(grep -n 'resolve-memory-dir\.sh' "$SETUP" | head -n1 | cut -d: -f1)"
if [ -n "$gitconfig_line" ] && [ -n "$memory_line" ] && [ "$gitconfig_line" -lt "$memory_line" ]; then
  ok "setup.sh links gitconfig before resolving claude-memory"
else
  ng "setup.sh: gitconfig at line ${gitconfig_line:-none}, memory resolve at line ${memory_line:-none}"
fi
```

- [ ] **Step 5: テストを実行して失敗を確認**

Run: `bash tests/claude-memory-ghq.sh`
Expected: 追加分だけ NG(setup.sh がまだ `resolve-memory-dir.sh` を呼んでいないため `memory_line` が空)

- [ ] **Step 6: 【behavioral】claude-memory セクションを置換**

`setup.sh` の claude-memory セクション:

```bash
# claude-memory (個人永続記憶, private repo) を ~/.claude/memory として参照させる。
# symlink は dotfiles の .gitignore (claude/* デフォルト無視) により追跡されない。
CLAUDE_MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/dev/claude-memory}"
if [ ! -d "${CLAUDE_MEMORY_DIR}" ]; then
  # private repo なので認証必須。ssh 鍵 → gh の順に試し、両方だめなら
  # メッセージだけ出して続行する (setup.sh 全体を止めない)。
  git clone git@github.com:shishi/claude-memory.git "${CLAUDE_MEMORY_DIR}" 2>/dev/null \
    || gh repo clone shishi/claude-memory "${CLAUDE_MEMORY_DIR}" 2>/dev/null \
    || echo "setup.sh: could not clone claude-memory (ssh key / gh auth missing?); clone manually: git clone git@github.com:shishi/claude-memory.git ${CLAUDE_MEMORY_DIR}"
fi
if [ -d "${CLAUDE_MEMORY_DIR}" ]; then
  if [ ! -e "${DOTDIR}/claude/memory" ] || [ -L "${DOTDIR}/claude/memory" ]; then
    ln -sfn "${CLAUDE_MEMORY_DIR}" "${DOTDIR}/claude/memory"
  else
    echo "setup.sh: ${DOTDIR}/claude/memory exists as a directory; skip (manual setup required)"
  fi
else
  echo "setup.sh: ${CLAUDE_MEMORY_DIR} not available; skip memory symlink"
fi
```

を以下に置換する:

```bash
# claude-memory (個人永続記憶, private repo) を ~/.claude/memory として参照させる。
# 配置先は claude/resolve-memory-dir.sh が解決する (ghq.root 対応・旧パスからの
# 安全な自動移行込み)。symlink は dotfiles の .gitignore により追跡されない。
CLAUDE_MEMORY_DIR="$(DOTDIR="$DOTDIR" bash "${DOTDIR}/claude/resolve-memory-dir.sh")"
resolve_status=$?
# setup.sh には set -e がないため、ヘルパーの失敗や壊れた出力 (空・複数行・
# 相対パス) をここで検証しないと後続の clone/symlink が変な場所に走る。
case "$CLAUDE_MEMORY_DIR" in
  "") resolve_status=1 ;;
  *"
"*) resolve_status=1 ;;
  /*) ;;
  *) resolve_status=1 ;;
esac
if [ "$resolve_status" -ne 0 ]; then
  echo "setup.sh: could not resolve claude-memory location; skip memory setup"
else
  if [ ! -d "${CLAUDE_MEMORY_DIR}" ]; then
    # ghq root 配下の中間ディレクトリ (github.com/shishi) は fresh 環境に
    # 存在せず、git clone は親を作らない。
    mkdir -p "$(dirname "${CLAUDE_MEMORY_DIR}")"
    # private repo なので認証必須。ssh 鍵 → gh の順に試し、両方だめなら
    # メッセージだけ出して続行する (setup.sh 全体を止めない)。
    git clone git@github.com:shishi/claude-memory.git "${CLAUDE_MEMORY_DIR}" 2>/dev/null \
      || gh repo clone shishi/claude-memory "${CLAUDE_MEMORY_DIR}" 2>/dev/null \
      || echo "setup.sh: could not clone claude-memory (ssh key / gh auth missing?); clone manually: git clone git@github.com:shishi/claude-memory.git ${CLAUDE_MEMORY_DIR}"
  fi
  if [ -d "${CLAUDE_MEMORY_DIR}" ]; then
    if [ ! -e "${DOTDIR}/claude/memory" ] || [ -L "${DOTDIR}/claude/memory" ]; then
      ln -sfn "${CLAUDE_MEMORY_DIR}" "${DOTDIR}/claude/memory"
    else
      echo "setup.sh: ${DOTDIR}/claude/memory exists as a directory; skip (manual setup required)"
    fi
  else
    echo "setup.sh: ${CLAUDE_MEMORY_DIR} not available; skip memory symlink"
  fi
fi
```

- [ ] **Step 7: テストを実行して成功を確認**

Run: `bash -n setup.sh && bash tests/claude-memory-ghq.sh && bash tests/setup-windows-symlinks.sh`
Expected: syntax OK、`tests/claude-memory-ghq.sh` が `PASS=26 FAIL=0`(25 + 順序検証)、Windows テストも全 ok

- [ ] **Step 8: 【behavioral】コミット**

```bash
git add setup.sh tests/claude-memory-ghq.sh
git commit -m "feat(setup): place claude-memory via resolve-memory-dir helper

clone 先の決定を固定パスからヘルパー呼び出しに置き換え、ghq.root が
ある環境では ghq 規約パスに配置・移行されるようにする。

setup.sh には set -e がないため、ヘルパーの非 0 終了や壊れた stdout
(空・複数行・相対パス) は検証で弾き、claude-memory セクション全体を
スキップする (壊れた値のまま clone/symlink が走るのを防ぐ)。clone 前の
mkdir -p は ghq root 配下の中間ディレクトリが fresh 環境に無いため。"
```

---

### Task 4: 検証ゲートと実機移行

**Files:**
- Modify: なし(検証と運用のみ)

**Interfaces:**
- Consumes: Task 1〜3 の全成果物

- [ ] **Step 1: 全テストスイートを実行**

Run: `bash tests/claude-memory-ghq.sh && bash tests/setup-windows-symlinks.sh && bash tests/compact-safety.sh`
Expected: すべて FAIL=0 / exit 0

- [ ] **Step 2: codex-review(native モード)を実行**

codex-review skill に従い、Task 1〜3 のコミットを native モードでレビューする(範囲指定: `--base` に実装開始前のコミット)。指摘があれば fix→re-review を clean まで反復する。

- [ ] **Step 3: 実機での移行(ユーザー確認必須)**

**この step は実データ(`~/dev/claude-memory`)を動かすため、実行前に必ずユーザーへ確認する。**

確認後に実行:

```bash
cd ~/dev/src/github.com/shishi/dotfiles
git -C ~/dev/claude-memory status --short   # 未コミット変更がないこと
DOTDIR="$PWD" bash claude/resolve-memory-dir.sh
```

Expected: stderr に `migrated ... -> .../dev/src/github.com/shishi/claude-memory`、stdout に新パス。続けて:

```bash
ln -sfn ~/dev/src/github.com/shishi/claude-memory claude/memory
ls -l claude/memory        # 新パスを指す symlink
ghq list | grep claude-memory   # ghq からも見える
git -C ~/dev/src/github.com/shishi/claude-memory status   # repo が健全
```

- [ ] **Step 4: 個人永続記憶を更新**

`~/.claude/memory/projects/github.com-shishi-dotfiles.md` の「本体 `~/dev/claude-memory`」の記述を新パス `~/dev/src/github.com/shishi/claude-memory` に更新し、記憶リポジトリで commit(`chore(memory): claude-memory を ghq 配置へ移行`)して `push origin main` する。

---

## Self-Review(実施済み)

- **Spec coverage:** パス解決(Task 1)、移行+fail closed(Task 2)、setup.sh 3 変更+.gitignore(Task 1, 3)、テスト 1〜16+順序検証(Task 1〜3)。spec の全要件にタスクあり。
- **Placeholder scan:** TBD/TODO なし。全 step に実コード・実コマンド・期待結果あり。
- **Type consistency:** ヘルパーの関数名(`warn`/`canon`/`absolutize`/`is_claude_memory_clone`)と変数(`old`/`new`/`link`/`REPO_PATH`)は Task 1↔2 で一致。テストのヘルパー呼び出しシグネチャも全タスクで同一。
