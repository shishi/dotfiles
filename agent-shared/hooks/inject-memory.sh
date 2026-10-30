#!/usr/bin/env bash
# SessionStart は索引・CORE・プロジェクト、UserPromptSubmit は索引と検索候補を渡す。
# Claude の SessionStart は hook 出力 1 つあたりの文字数上限に収めるため、core と project の
# 2 つの hook に分ける。索引は毎入力の lookup で届くので、Claude の起動時には出さない。
# 起動時の異常は警告で伝え、lookup の失敗は exit 2 で入力の処理を止める。
# usage: inject-memory.sh [MEMORY_DIR] [core|project|lookup [検索語...]]
set -u

MEMORY_DIR="${1:-${HOME}/.claude/memory}"
mode="${2:-startup}"
# UserPromptSubmit は検索失敗を握りつぶして作業開始しない。SessionStart は従来どおり。
if [ "$mode" = lookup ]; then
  trap 'echo "記憶の検索・取得が未完了のため、この入力での作業は開始していません。" >&2; exit 2' EXIT
fi

# 壊れた link: ディレクトリエントリ自体は存在するのに先が解決できない。
# POSIX symlink は -L で判定できるが、Windows junction は git-bash の -L で
# 拾えない場合があるため、「親ディレクトリにエントリが在るのに -e が偽」も
# 壊れ link とみなす。「記憶が静かに消えたまま動き続ける」事故の検知が目的。
if [ ! -e "$MEMORY_DIR" ]; then
  if [ -L "$MEMORY_DIR" ] \
    || ls -A "$(dirname "$MEMORY_DIR")" 2>/dev/null | grep -qxF "$(basename "$MEMORY_DIR")"; then
    echo "<personal-memory-warning>記憶ディレクトリの link が壊れています: ${MEMORY_DIR}(リンク先が存在しない)</personal-memory-warning>"
  fi
  exit 0
fi

# MEMORY.md が無い directory は未導入として無言で扱う。一方、MEMORY.md があるのに
# Git worktree でない実体は editable file を注入しない。commit snapshot だけを信頼する。
if [ ! -e "${MEMORY_DIR}/.git" ]; then
  if [ -f "${MEMORY_DIR}/MEMORY.md" ]; then
    echo "<personal-memory-warning>記憶ディレクトリが Git repo ではないため注入をスキップ: ${MEMORY_DIR}。MEMORY.md の内容は読み取っていません</personal-memory-warning>"
  fi
  exit 0
fi

is_num() { # $1 が空でない十進数か(外部コマンドの出力を算術展開へ渡す前の検査)
  case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

# 同じイベントの hook は並列に走るため、同期は 1 つの hook だけで行う。
# Claude の project は同期を待たずに読み、その古さを未同期と同じく出力で伝える。
sync_note=""
pre_sync=""
if [ "$mode" = core ]; then
  pre_sync=$(git -C "$MEMORY_DIR" rev-parse --verify -q 'main^{commit}' 2>/dev/null | tr -d '\r')
fi
if [ "$mode" != lookup ] && [ "$mode" != project ]; then
  sync_helper="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/memory-write-preflight.sh"
  if bash "$sync_helper" "$MEMORY_DIR" --read-sync >/dev/null 2>&1; then
    sync_note="記憶の同期: origin/main と同期済み"
  else
    sync_note="⚠ 記憶は未同期(通信失敗・時間切れ・書き込み中・Git 状態など)。以下はローカルの確定済み記憶。別端末の最新変更が必要なら同期状態を確認すること"
  fi
fi

# --- git-state aware 読み取りの準備 ---
# MEMORY.md の存在確認より先に Git の健全性を検査する(編集途中で MEMORY.md が
# 消えている dirty repo を無言スキップに落とさない)。健全なら main commit を一度だけ
# 固定し、以降はその snapshot だけを読む。
snapshot=""
ahead_warn=""
degraded=""
repo_state=""
if [ -e "${MEMORY_DIR}/.git" ]; then
  branch=$(git -C "$MEMORY_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null | tr -d '\r')
  gitdir=$(git -C "$MEMORY_DIR" rev-parse --absolute-git-dir 2>/dev/null | tr -d '\r')
  # 中止(fatal)と劣化注入(degraded)を分ける。
  # 中止: HEAD の内容自体が「注入してよい記憶」でない状態。
  # 劣化注入: HEAD は健全で書き込みが進行中なだけの状態。注入は下の snapshot 経由で
  #   常に committed 内容だけを読むので、編集途中の worktree を掴む危険は無い。
  #   ここで注入をゼロにすると subagent が記憶なしで走り、記録済みの罠を再発見できず
  #   誤った結論を出す(注入しないことの害のほうが大きい)。
  fatal=""
  # rebase/merge を branch より先に見る。rebase 中断中は HEAD が detached になり branch が
  # "HEAD" と読めるため、branch を先に評価すると実態が「ブランチが main ではない (HEAD)」に
  # 化けて、読み手が rebase 中断だと気づけない。
  if [ -n "$gitdir" ] && { [ -e "$gitdir/rebase-merge" ] || [ -e "$gitdir/rebase-apply" ] || [ -e "$gitdir/MERGE_HEAD" ]; }; then
    fatal="rebase/merge が進行中"
  elif [ -z "$gitdir" ]; then
    # .git は在るのに git dir が解決できない = repo として読めない(gitdir 先が不在の
    # .git ファイル、壊れた repo)。下の HEAD 検査もここで失敗するため、先に切り分ける。
    # 「commit が無い」と誤診すると記憶が空だと伝わり、作り直しへ誘導しうる。
    fatal=".git があるのに git repo として読めない"
  elif ! git -C "$MEMORY_DIR" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    # commit が無い repo では abbrev-ref HEAD が exit 128 で "HEAD" を返すため、branch
    # 判定に落とすと「ブランチが main ではない (HEAD)」と誤診する。
    # 「未 commit」「orphan ブランチ」「ref を失った」は git から区別できない(いずれも
    # symbolic-ref は成功し verify は失敗する)ため、記憶が空だと断定せず候補を並べる。
    fatal="HEAD から commit を解決できない(未 commit / orphan ブランチ / repo 破損)"
  elif [ "$branch" != "main" ]; then
    fatal="ブランチが main ではない (${branch})"
  fi
  if [ -n "$fatal" ]; then
    # 復旧手順は worktree ではなく main の commit を指す。fatal は「HEAD / worktree の
    # 内容を信用しない」判定なので、同じ内容を直接読ませたら判定の意味が消える。
    # 案内するコマンドはそのまま実行される前提なので、パスは %q で shell-safe にし、
    # 実際に読む path が main に在るときだけ案内する(ref の有無だけでは足りない)。
    if git -C "$MEMORY_DIR" cat-file -e main:MEMORY.md 2>/dev/null; then
      mem_q=$(printf '%q' "$MEMORY_DIR")
      recovery="記憶が要る作業の前に \`git -C ${mem_q} show main:MEMORY.md\` で main の内容を読むこと(他のファイルも \`git -C ${mem_q} show main:<repo 相対パス>\` で読む。worktree と HEAD は信用しない)"
    else
      recovery="main から読める索引が無いため、記憶が要る作業の前にユーザーへ報告すること"
    fi
    echo "<personal-memory-warning>記憶 repo が不健全なため注入をスキップ: ${fatal}(${MEMORY_DIR})。${recovery}</personal-memory-warning>"
    exit 0
  fi
  # 並列に走る同期の fast-forward と index.lock を取り合わないよう、index の refresh を書かない。
  if ! porcelain=$(git --no-optional-locks -C "$MEMORY_DIR" status --porcelain 2>/dev/null); then
    echo "<personal-memory-warning>記憶 repo の Git 状態を確認できないため注入をスキップしました</personal-memory-warning>"
    exit 0
  fi
  if [ -n "$gitdir" ] && [ -d "$gitdir/memory-write.lock" ]; then
    # mtime は GNU 形式 (-c %Y) と BSD 形式 (-f %m) を順に試し、**試行ごとに数値検査して
    # 数値だけを採用する**。GNU の `stat -f` は filesystem 情報の表示で %m はマウント
    # ポイントを返すため、`A || B` で合成すると非数値を exit 0 で掴んでしまい、GNU 環境で
    # stale 検知が永久に発火しない。数値検査が本体で、試行順そのものは結果を変えない。
    lock_epoch=$(stat -c %Y "$gitdir/memory-write.lock" 2>/dev/null | tr -d '\r')
    is_num "$lock_epoch" || lock_epoch=$(stat -f %m "$gitdir/memory-write.lock" 2>/dev/null | tr -d '\r')
    # 経過時間は「両端が数値で、かつ lock が過去」のときだけ算出する。非数値を算術展開に
    # 入れると set -u が hook を落とし、注入も警告も消える(冒頭の exit 0 契約に反する)。
    # 未来 mtime(時計ずれ)で負の分数を表示しないためにも、ここで弾いてから計算する。
    now_epoch=$(date +%s 2>/dev/null | tr -d '\r')
    lock_min=""
    if is_num "$lock_epoch" && is_num "$now_epoch" && [ "$now_epoch" -ge "$lock_epoch" ]; then
      lock_min=$(( (now_epoch - lock_epoch) / 60 ))
    fi
    if [ -z "$lock_min" ]; then
      repo_state="記憶 repo に write lock あり(取得時刻は不明)"
    elif [ "$lock_min" -ge 10 ]; then
      repo_state="記憶 repo の write lock が ${lock_min} 分前から残存(10 分以上 = 要調査。参考情報として放置せず、元の作業より先に状態を調査。現在の workflow が継続中なら通常の finish まで保持、中断時だけ release して以後の変更を禁止。所有者不明なら自動 release・raw delete せず具体的状態を報告して復旧まで停止)"
    else
      repo_state="記憶 repo に write lock あり(${lock_min} 分前に取得・書き込み進行中)"
    fi
    # lock と dirty は同時に成立する(書き込み途中で落ちたセッション)。自律復旧できるか
    # 判断するには未 commit の変更が残っているかが要るので、片方に畳まず両方伝える。
    [ -n "$porcelain" ] && repo_state="${repo_state}。worktree に未 commit の変更あり"
  elif [ -n "$porcelain" ]; then
    repo_state="記憶 repo の worktree が dirty(編集途中)"
  fi
  # 注入する経路の文言。repo_state は注入しない経路(下の索引なし警告)でも使うため、
  # 「以下は…」のような注入前提の文はここでだけ付ける。
  [ -n "$repo_state" ] && degraded="⚠ ${repo_state}。以下は最後の commit 時点の内容"
  # チェック直後に別 process が branch を切り替えても consolidation 内容を掴まないよう、
  # HEAD ではなく main ref を固定する。失敗時に worktree へフォールバックしない。
  if ! snapshot=$(git -C "$MEMORY_DIR" rev-parse --verify 'main^{commit}' 2>/dev/null); then
    echo "<personal-memory-warning>記憶 repo の main commit を固定できないため注入をスキップ: ${MEMORY_DIR}。worktree と HEAD は読み取っていません</personal-memory-warning>"
    exit 0
  fi
  snapshot=$(printf '%s' "$snapshot" | tr -d '\r')
  if [ -z "$snapshot" ]; then
    echo "<personal-memory-warning>記憶 repo の main commit を固定できないため注入をスキップ: ${MEMORY_DIR}。worktree と HEAD は読み取っていません</personal-memory-warning>"
    exit 0
  fi
  # 未 push commit はローカルに実在する確定済み記憶なので注入するが、警告を添える
  ahead=$(git -C "$MEMORY_DIR" rev-list --count 'main@{upstream}..main' 2>/dev/null | tr -d '\r')
  if is_num "$ahead" && [ "$ahead" -gt 0 ]; then
    ahead_warn="⚠ 未 push の記憶 commit が ${ahead} 件あります(前回 push 失敗の可能性。次の書き込み前に解消すること)"
  fi
fi

emit_file() { # $1=repo 相対パス
  git -C "$MEMORY_DIR" show "${snapshot}:$1" 2>/dev/null
}
probe_file() { # $1=repo 相対パス; 0=存在、1=正常な不存在、2=Git異常
  if tree_entry=$(git -C "$MEMORY_DIR" ls-tree --name-only "$snapshot" -- "$1" 2>/dev/null); then
    [ -n "$tree_entry" ]
    return
  fi
  return 2
}

# 記憶未導入(索引なし)は正常系として無言スキップ。ただし worktree に索引が在るのに
# snapshot に無い場合は「注入したつもりで記憶ゼロ」になるため黙らない(注入は snapshot
# 経由なので未 commit の索引は出せない = 出せないことを伝えるしかない)。
probe_file "MEMORY.md"
index_probe_status=$?
case "$index_probe_status" in
  0) ;;
  1)
    if [ -f "${MEMORY_DIR}/MEMORY.md" ]; then
      # lock 保持中なら worktree の索引は書き込み途中の可能性があるので、下書きを読ませる
      # 前にその事実を渡す(repo_state はここまでに算出済み)。
      state_note=""
      [ -n "$repo_state" ] && state_note="${repo_state}。"
      echo "<personal-memory-warning>記憶 repo の commit 済みの索引が読めません(未 commit または object 欠損): ${MEMORY_DIR}。注入なし。${state_note}記憶が要る作業の前に ${MEMORY_DIR}/MEMORY.md を未 commit の下書きとして Read し、その旨をユーザーへ報告すること</personal-memory-warning>"
    fi
    exit 0
    ;;
  *)
    echo "<personal-memory-warning>記憶 snapshot の存在確認に失敗したため注入をスキップ: MEMORY.md。本文は出力していません</personal-memory-warning>"
    exit 0
    ;;
esac

if [ "$#" -ge 3 ] && [ "$mode" = lookup ]; then
  shift 2
  input=$(jq -n --arg prompt "$*" '{prompt:$prompt,memory_lookup_manual:true}')
else
  input=$(cat 2>/dev/null || true)
fi
cwd=""
if command -v jq >/dev/null 2>&1; then
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null | tr -d '\r')
fi
[ -n "$cwd" ] || cwd="$PWD"
if command -v cygpath >/dev/null 2>&1; then
  cwd=$(cygpath -u "$cwd" 2>/dev/null || printf '%s' "$cwd")
fi

slugify() { printf '%s' "$1" | tr ':/\\' '-'; }

normalize_remote() {
  # ssh/https/scp 形式を host/owner/repo へ正規化(.git / user@ / scheme を除去)
  local url="$1"
  url="${url%.git}"
  url="${url#ssh://}"
  url="${url#git+ssh://}"
  url="${url#git://}"
  url="${url#https://}"
  url="${url#http://}"
  url="${url#*@}"
  url="${url//:/\/}"
  printf '%s' "$url"
}

slug=""
origin=$(git -C "$cwd" remote get-url origin 2>/dev/null | tr -d '\r' || true)
if [ -n "$origin" ]; then
  slug=$(slugify "$(normalize_remote "$origin")")
fi

if [ -z "$slug" ]; then
  ghq_root=$({ ghq root 2>/dev/null || git config --get ghq.root 2>/dev/null; } | head -1 | tr -d '\r')
  ghq_root="${ghq_root/#\~/$HOME}"
  [ -n "$ghq_root" ] || ghq_root="$HOME/ghq"
  if command -v cygpath >/dev/null 2>&1; then
    ghq_root=$(cygpath -u "$ghq_root" 2>/dev/null || printf '%s' "$ghq_root")
  fi
  case "$cwd" in
    "$ghq_root"/*) slug=$(slugify "${cwd#"$ghq_root"/}") ;;
  esac
fi

[ -n "$slug" ] || slug=$(slugify "$cwd")

# required index、optional CORE、存在する selected project file は、wrapper を出す前に
# 固定 snapshot から各 1 回だけ読み切る。途中失敗時に partial wrapper を残さない。
if ! memory_content=$(emit_file "MEMORY.md"); then
  echo "<personal-memory-warning>記憶 snapshot の読み取りに失敗したため注入をスキップ: MEMORY.md(${MEMORY_DIR})。worktree は読み取っていません</personal-memory-warning>"
  exit 0
fi

core_content=""
core_present=""
probe_file "CORE.md"
core_probe_status=$?
case "$core_probe_status" in
  0)
    if ! core_content=$(emit_file "CORE.md"); then
      echo "<personal-memory-warning>記憶 snapshot の読み取りに失敗したため注入をスキップ: CORE.md(${MEMORY_DIR})。worktree は読み取っていません</personal-memory-warning>"
      exit 0
    fi
    core_present=1
    ;;
  1) ;;
  *)
    echo "<personal-memory-warning>記憶 snapshot の存在確認に失敗したため注入をスキップ: CORE.md。本文は出力していません</personal-memory-warning>"
    exit 0
    ;;
esac

project_path="projects/${slug}.md"
project_content=""
project_present=""
probe_file "$project_path"
project_probe_status=$?
case "$project_probe_status" in
  0)
    if ! project_content=$(emit_file "$project_path"); then
      echo "<personal-memory-warning>記憶 snapshot の読み取りに失敗したため注入をスキップ: ${project_path}(${MEMORY_DIR})。worktree は読み取っていません</personal-memory-warning>"
      exit 0
    fi
    project_present=1
    ;;
  1) ;;
  *)
    echo "<personal-memory-warning>記憶 snapshot の存在確認に失敗したため注入をスキップ: ${project_path}。本文は出力していません</personal-memory-warning>"
    exit 0
    ;;
esac

secret_pattern="(^|[^[:alnum:]_])(password|passwd|secret|token|api[_-]?key|private[_-]?key|client[_-]?secret)[\"']?[[:space:]]*[:=][[:space:]]*(\"[^\"]{8,}\"|'[^']{8,}'|[^[:space:]\"'][^[:space:]\"']{7,})|(gh[pousr]_|github_pat_|xox[baprs]-|sk-)[[:alnum:]_=-]{20,}|AKIA[A-Z0-9]{16}|-----BEGIN [A-Z0-9 ]*PRIVATE KEY( BLOCK)?-----"
scan_content() { # $1=content; 0=secret candidate, 1=clean, other=scan error
  printf '%s\n' "$1" | LC_ALL=C grep -Eiq -- "$secret_pattern"
}

scan_path() { # $1=repo relative path $2=content; warning を出したら 0、clean なら 1
  scan_content "$2"
  scan_status=$?
  case "$scan_status" in
    0)
      echo "<personal-memory-warning>秘密情報の可能性があるため記憶注入をスキップ: $1。値と本文は出力していません。該当内容を除去してから再実行してください</personal-memory-warning>"
      return 0
      ;;
    1)
      return 1
      ;;
    *)
      echo "<personal-memory-warning>記憶 snapshot の秘密情報検査に失敗したため注入をスキップ: $1。本文は出力していません</personal-memory-warning>"
      return 0
      ;;
  esac
}

scan_path "MEMORY.md" "$memory_content" && exit 0
if [ -n "$core_present" ]; then
  scan_path "CORE.md" "$core_content" && exit 0
fi
if [ -n "$project_present" ]; then
  scan_path "$project_path" "$project_content" && exit 0
fi

lookup_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/search-memory.py"
py_bin=$(command -v python3 || command -v python) || py_bin=""
if [ "$mode" = lookup ]; then
  [ -n "$py_bin" ] || exit 2
  if printf '%s' "$input" | "$py_bin" "$lookup_script" "$MEMORY_DIR" "$snapshot" lookup "$project_path" "$secret_pattern"; then
    trap - EXIT
    exit 0
  fi
  exit 2
fi
# 圧縮・再開を含む新コンテキストでは取得済み状態をリセットする。既読として記録するのは、
# この出力が全文を渡す文書だけにする。Claude では並列に走る 2 つの hook が同じ記録を
# 書き合わないよう、project 側が共有の記録をリセットし、core 側は CORE を別の記録に書く。
if [ -n "$py_bin" ] && [ "$mode" != core ] && [ "$mode" != project ]; then
  printf '%s' "$input" | "$py_bin" "$lookup_script" "$MEMORY_DIR" "$snapshot" reset "$project_path" "$secret_pattern" || true
fi

# Claude は hook 出力 1 つあたり 10,000 文字を超えると、先頭だけのプレビューに置き換えて
# 本文を渡さない。超える場合は本文の代わりに、確定 commit から全文を読む手順を渡す。
if [ "$mode" = core ] || [ "$mode" = project ]; then
  claude_limit=10000
  if [ "$mode" = core ]; then
    tag=personal-memory
    header="個人永続記憶の全体価値観と方針。索引は毎入力の <personal-memory-index>、プロジェクト記憶は別の起動時 hook で渡す。詳細は ${MEMORY_DIR}/ 配下を必要時に Read で開くこと。"
    project_note=""
    if [ -n "$pre_sync" ] && [ "$pre_sync" != "$snapshot" ] \
      && ! git -C "$MEMORY_DIR" diff --quiet "$pre_sync" "$snapshot" -- "$project_path" 2>/dev/null; then
      project_note="⚠ 起動時の同期でプロジェクト記憶(${project_path})が同期で更新された。別の起動時 hook が渡した本文は同期前の版なので、作業前に lookup で $(printf '%q' "$project_path") を取得し直すこと"
    fi
    notes=("$sync_note" "$degraded" "$ahead_warn" "$project_note")
    doc_path="CORE.md" doc_present="$core_present" doc_content="$core_content"
    doc_title="## 全体価値観と方針"
  else
    tag=personal-memory-project
    header="個人永続記憶のプロジェクト記憶。"
    if [ -n "$project_present" ]; then
      slug_note="現在のプロジェクト slug: ${slug}(プロジェクト記憶: ${project_path})"
    elif [ -n "$degraded" ]; then
      slug_note="現在のプロジェクト slug: ${slug}(プロジェクト記憶: 最後の commit 時点ではなし)"
    else
      slug_note="現在のプロジェクト slug: ${slug}(プロジェクト記憶: なし)"
    fi
    notes=("⚠ 起動時の同期を待たずに読んだローカルの確定済み記憶(同期は並列に走る CORE 側の起動時 hook が行う)。未同期の記憶と同じく、別端末の最新変更が必要なら lookup で取得し直すこと" "$slug_note" "$degraded")
    doc_path="$project_path" doc_present="$project_present" doc_content="$project_content"
    doc_title="## プロジェクト記憶 (${slug})"
  fi
  render() { # $1=本文。空なら header と注記だけ
    printf '<%s>\n%s\n' "$tag" "$header"
    for note in "${notes[@]}"; do
      [ -n "$note" ] && printf '%s\n' "$note"
    done
    [ -n "$1" ] && printf '\n%s\n' "$1"
    printf '</%s>\n' "$tag"
  }
  body=""
  [ -n "$doc_present" ] && body=$(printf '%s\n%s' "$doc_title" "$doc_content")
  output=$(render "$body")
  # Claude の文字数は UTF-16 の単位で数える。数えられないときは本文をそのまま出す。
  chars=""
  if [ -n "$py_bin" ]; then
    chars=$(printf '%s' "$output" | "$py_bin" -c 'import sys; print(len(sys.stdin.buffer.read().decode("utf-8", "replace").encode("utf-16-le")) // 2)' 2>/dev/null | tr -d '\r')
  fi
  delivered="$doc_path"
  if is_num "$chars" && [ "$chars" -ge "$claude_limit" ]; then
    mem_q=$(printf '%q' "$MEMORY_DIR")
    show_q=$(printf '%q' "${snapshot}:${doc_path}")
    output=$(render "<personal-memory-warning>${doc_path} を含む起動時の注入が ${chars} 文字で、Claude の hook 出力上限(${claude_limit} 文字)を超えるため本文を省略しました。作業前に \`git -C ${mem_q} show ${show_q}\` で全文を読むこと</personal-memory-warning>")
    delivered=""
  fi
  [ -n "$doc_present" ] || delivered=""
  if [ -n "$py_bin" ]; then
    record_mode=reset-project
    [ "$mode" = core ] && record_mode=record-core
    printf '%s' "$input" | "$py_bin" "$lookup_script" "$MEMORY_DIR" "$snapshot" "$record_mode" "$delivered" "$secret_pattern" || true
  fi
  printf '%s\n' "$output"
  exit 0
fi

echo "<personal-memory>"
echo "個人永続記憶。詳細は ${MEMORY_DIR}/ 配下を必要時に Read で開くこと。"
[ -n "$sync_note" ] && echo "$sync_note"
if [ -n "$project_present" ]; then
  echo "現在のプロジェクト slug: ${slug}(プロジェクト記憶: ${project_path})"
elif [ -n "$degraded" ]; then
  echo "現在のプロジェクト slug: ${slug}(プロジェクト記憶: 最後の commit 時点ではなし)"
else
  echo "現在のプロジェクト slug: ${slug}(プロジェクト記憶: なし)"
fi
[ -n "$degraded" ] && echo "$degraded"
[ -n "$ahead_warn" ] && echo "$ahead_warn"
echo ""
printf '%s\n' "$memory_content"
if [ -n "$core_present" ]; then
  echo ""
  echo "## 全体価値観と方針"
  printf '%s\n' "$core_content"
fi
if [ -n "$project_present" ]; then
  echo ""
  echo "## プロジェクト記憶 (${slug})"
  printf '%s\n' "$project_content"
fi
echo "</personal-memory>"
exit 0
