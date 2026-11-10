#!/usr/bin/env bash
# Derived from superpowers 7.0.2 (https://github.com/obra/superpowers), MIT License. See ../../superpowers.LICENSE
#
# テストを 1 ファイルずつ実行し、不要なファイル・ディレクトリを作ったテストを特定する。
# 使い方: find-polluter.sh <検査するパス> <テストファイルの find -path パターン> <テストコマンド...>
# テストコマンドの末尾にテストファイルのパスを付けて実行する。
# 例: find-polluter.sh .git 'src/**/*.test.ts' npx vitest run
#     find-polluter.sh tmp/leak 'spec/**/*_spec.rb' bundle exec rspec
# 終了コード: 0 = 見つからない、1 = 見つけた、2 = 使い方の誤り、開始前から検査対象が存在する、またはテストコマンドを実行できない。
set -u

if [ $# -lt 3 ]; then
  echo "使い方: $0 <検査するパス> <テストファイルの find -path パターン> <テストコマンド...>" >&2
  exit 2
fi

pollution=$1
pattern=${2#./}
shift 2

# 開始前から存在すると、どのテストが作ったか判別できない。
if [ -e "$pollution" ]; then
  echo "開始前から存在します: $pollution (削除してから再実行してください)" >&2
  exit 2
fi

# find -path の '**/' は 0 階層に一致しないため、'**/' を除いたパターンでも探す。-o で結ぶので同じファイルは一度だけ出る。
files=()
while IFS= read -r -d '' f; do
  files+=("$f")
done < <(find . \( -path "./$pattern" -o -path "./${pattern//\*\*\//}" \) -type f -print0)

total=${#files[@]}
if [ "$total" -eq 0 ]; then
  echo "パターンに一致するテストファイルがありません: $pattern" >&2
  exit 2
fi
echo "検査対象: $pollution / テストファイル $total 件"

log=$(mktemp) || { echo "一時ファイルを作れません" >&2; exit 2; }
count=0
runnable=0
for f in "${files[@]}"; do
  count=$((count + 1))
  echo "[$count/$total] $f"
  # テスト自体の成否は問わない。作られたかどうかだけを見る。
  "$@" "$f" >"$log" 2>&1
  status=$?
  # 126・127 はテストコマンド自体を実行できなかったことを示す。全件がそうなら何も確かめていない。
  case $status in 126 | 127) ;; *) runnable=1 ;; esac
  if [ -e "$pollution" ]; then
    echo
    echo "作ったテスト: $f (テストの終了コード $status)"
    ls -ld "$pollution"
    echo "テストの出力: $log"
    exit 1
  fi
done

if [ "$runnable" -eq 0 ]; then
  echo "テストコマンドを実行できませんでした (終了コード $status)。最後の出力: $log" >&2
  exit 2
fi
rm -f "$log"
echo "どのテストも $pollution を作りませんでした。"
exit 0
