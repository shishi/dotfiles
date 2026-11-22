---
name: secrets-scan
description: |
  gitleaks で、commit・外部 API 送信の前に、作業ツリーの未コミット変更(worktree vs HEAD + untracked)と
  呼び出し元が渡すファイル(commit 済み差分・Git 外の本文・外部 CLI への入力)から
  設定済みパターンに一致する secrets を検出する。review-gate などの手順から呼ばれる、
  または /secrets-scan で明示発動。検出ゼロが通過条件。
---

# Secrets scan (gitleaks)

commit・外部 API 送信の前に、送る内容を gitleaks の検出規則で検査する。
検出ゼロは公開適否の証明ではない。個人マシン名・私的なパス・作業メモなど、読者と用途に
合わない情報の混入は writing-prose に従って選別し、spec-scope レーンでも確認する。

## 対象(この範囲を満たさない省略形を使わない)

- 作業ツリー: worktree vs HEAD の全変更 + untracked ファイル。staged だけを見る形
  (`gitleaks protect --staged`)は不可。Git repo の中で実行するときの既定。
- 呼び出し元が渡すファイル: commit・送信する内容のうち作業ツリーの検査に現れないものは、
  呼び出し元がファイルにして絶対パスで渡す。基準版からの commit 済み差分
  (`git diff <基準版>..HEAD` をリポジトリ外のファイルへ書き出したもの)、PR の差分と本文、
  issue などの Git 外の本文、外部 CLI へ渡すプロンプト・入力ファイルがこれに当たる。
- 作業ツリーを外す場合: 固定した対象に手元の未コミット変更が含まれないとき
  (他者の PR だけのレビューなど) と、Git repo の外で実行するときは `scan_worktree=no` にし、
  渡したファイルだけを検査する。`scan_worktree=yes` のまま作業ツリーを取得できなければ止まる。
- 渡すファイルは通常ファイルにする。gitleaks はシンボリックリンクを読まないので、リンクは止まる。

## 手順

1. 同じサブシェルで、対象の列挙と検査を行う。`scan_files` に渡すファイルの絶対パスを入れ、
   作業ツリーを外す場合だけ `scan_worktree=no` にする。
   NUL 区切りで空白入りの名前を扱い、一時一覧は実行ごとに分ける。
   repo ルートの `.gitleaks.toml` は明示指定し、対象の読取失敗を検出ゼロとして扱わない。
   ```bash
   (
   scan_files=()      # 呼び出し元が渡すファイルの絶対パス。無ければ空のまま
   scan_worktree=yes  # 固定した対象に手元の未コミット変更が含まれないときだけ no
   scan_list=$(mktemp "${TMPDIR:-/tmp}/secrets-scan.XXXXXX") || exit 1
   trap 'rm -- "$scan_list"' EXIT
   cfg=()
   scan_root=
   if [ "$scan_worktree" = yes ]; then
     # 作業ツリーを列挙できないまま渡したファイルだけで通さない
     scan_root=$(git rev-parse --show-toplevel) || { echo 'NO WORKTREE: 作業ツリーを取得できない。Git 外の対象だけなら scan_worktree=no にする' >&2; exit 1; }
     cd "$scan_root" || exit 1
     { git diff --name-only -z --diff-filter=d HEAD && git ls-files --others --exclude-standard -z; } > "$scan_list" || exit 1
   elif scan_root=$(git rev-parse --show-toplevel 2>/dev/null); then
     cd "$scan_root" || exit 1
   fi
   [ -z "$scan_root" ] || [ ! -f "$scan_root/.gitleaks.toml" ] || cfg=(-c "$scan_root/.gitleaks.toml")
   for f in "${scan_files[@]}"; do
     case "$f" in (/*) ;; (*) printf 'NOT ABSOLUTE: %s\n' "$f" >&2; exit 1 ;; esac
     # gitleaks はシンボリックリンクを読まずに検出ゼロを返すので、リンクのまま渡さない
     [ ! -L "$f" ] || { printf 'SYMLINK: %s (送る本文を通常ファイルにして渡す)\n' "$f" >&2; exit 1; }
     printf '%s\0' "$f" >> "$scan_list" || exit 1
   done
   # 作業ツリーを見ない実行で対象が空なのは渡し忘れなので、検出ゼロとして通さない
   [ -s "$scan_list" ] || [ "$scan_worktree" = yes ] || { echo 'NO TARGET: scan_files に検査するファイルを渡す' >&2; exit 1; }
   found=0
   while IFS= read -r -d '' f; do
     if [ ! -f "$f" ] || [ ! -r "$f" ]; then
       printf 'READ FAILED: %s\n' "$f" >&2
       found=1
       continue
     fi
     gitleaks detect --no-git --source "$f" "${cfg[@]}" --exit-code 1 --no-banner || { printf 'SCAN FAILED: %s\n' "$f" >&2; found=1; }
   done < "$scan_list"
   [ "$found" -eq 0 ]
   )
   ```
2. 検出があれば該当箇所を除去・置換して再スキャン。読取・実行失敗は原因を解消する。
   **全対象を読み取って検査でき、検出ゼロになるまで通過しない。**

## gitleaks が無い場合

missing-tools skill で導入を試みる(Windows は同 skill の「Nix を使えない Windows」節が
scoop / winget の経路を持つ。scoop のパッケージ名は `gitleaks`)。導入不能なら
**このレーンをスキップせず停止してユーザーへ報告する**(public repo で secrets の
静かな素通りは偽の安心になる)。

## 誤検出(false positive)

repo ルートの `.gitleaks.toml` の allowlist で管理する:

```toml
[allowlist]
description = "reviewed false positives"
paths = ['''docs/example\.md''']
regexes = ['''EXAMPLE_[A-Z_]+''']
```

allowlist へ追加する前に、本当に secret でないことを人が確認する(追加はユーザー承認事項)。

注意: per-file 実行では `-c` で明示指定しないと allowlist が適用されない(上の手順 1 はこれを行っている)。
`paths` の allowlist は作業ツリーのファイルの相対パスに一致させる規則なので、リポジトリ外へ書き出した
差分ファイルには当たらない。差分ファイルでの誤検出は `regexes` で扱う。

## 制約

- この skill はマイルストーン判断を持たない。いつ走らせるか・どのファイルを渡すかは
  呼び出し元 (review-gate など) が決める(単独発動は任意タイミングで可)。
