---
name: secrets-scan
description: |
  gitleaks で uncommitted の変更(worktree vs HEAD の全変更 + untracked)から
  設定済みパターンに一致する secrets を検出する。review-gate のレーン0 として呼ばれる、
  または /secrets-scan で明示発動。検出ゼロが通過条件。
---

# Secrets scan (gitleaks)

uncommitted の内容を commit・外部 API 送信の前に、gitleaks の検出規則で検査する。
検出ゼロは公開適否の証明ではない。個人マシン名・私的なパス・作業メモなど、読者と用途に
合わない情報の混入は writing-prose に従って選別し、spec-scope レーンでも確認する。

## カバレッジ(この範囲を満たさない省略形を使わない)

worktree vs HEAD の全変更 + untracked ファイル。staged だけを見る形
(`gitleaks protect --staged`)は不可。

## 手順

1. repo ルートへ移動した同じサブシェルで、対象の列挙と検査を行う。
   NUL 区切りで空白入りの名前を扱い、一時一覧は実行ごとに分ける。
   `.gitleaks.toml` は明示指定し、対象の読取失敗を検出ゼロとして扱わない。
   ```bash
   (
   scan_root=$(git rev-parse --show-toplevel) || exit 1
   cd "$scan_root" || exit 1
   scan_list=$(mktemp "${TMPDIR:-/tmp}/secrets-scan.XXXXXX") || exit 1
   trap 'rm -f "$scan_list"' EXIT
   { git diff --name-only -z --diff-filter=d HEAD && git ls-files --others --exclude-standard -z; } > "$scan_list" || exit 1
   cfg=(); [ ! -f .gitleaks.toml ] || cfg=(-c "$scan_root/.gitleaks.toml")
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

注意: per-file 実行では `-c` で明示指定しないと allowlist が適用されない(上の手順 2 はこれを行っている)。

## 制約

- この skill はマイルストーン判断を持たない。いつ走らせるかは review-gate が決める
  (単独発動は任意タイミングで可)。
