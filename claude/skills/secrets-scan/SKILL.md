---
name: secrets-scan
description: |
  gitleaks で uncommitted の変更(worktree vs HEAD の全変更 + untracked)から
  secrets/PII を決定的に検出する。review-gate のレーン0 として呼ばれる、
  または /secrets-scan で明示発動。検出ゼロが通過条件。
---

# Secrets scan (gitleaks)

uncommitted の内容を commit・外部 API 送信の前に検査する。LLM ではなく決定的ツールで行う
(見逃しを確率的にしないため)。

## カバレッジ(この範囲を満たさない省略形を使わない)

worktree vs HEAD の全変更 + untracked ファイル。staged だけを見る形
(`gitleaks protect --staged`)は不可。

## 手順

1. 対象列挙:
   ```bash
   { git diff --name-only -z --diff-filter=d HEAD; git ls-files --others --exclude-standard -z; } > "${TMPDIR:-/tmp}/secrets-scan-files.z"
   ```
2. 各対象ファイルを検査(NUL 区切りで空白入りファイル名にも安全。repo ルートの
   `.gitleaks.toml` は明示指定しないと読まれない。検出があれば最終 exit 1):
   ```bash
   cfg=(); [ -f "$(git rev-parse --show-toplevel)/.gitleaks.toml" ] && cfg=(-c "$(git rev-parse --show-toplevel)/.gitleaks.toml")
   found=0
   while IFS= read -r -d '' f; do
     gitleaks detect --no-git --source "$f" "${cfg[@]}" --exit-code 1 --no-banner || { echo "LEAK: $f"; found=1; }
   done < "${TMPDIR:-/tmp}/secrets-scan-files.z"
   [ "$found" -eq 0 ]
   ```
3. 検出があれば該当箇所を除去・置換して再スキャン。**検出ゼロになるまで通過しない。**

## gitleaks が無い場合

missing-tools skill で導入を試みる(scoop: `scoop install gitleaks`)。導入不能なら
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
