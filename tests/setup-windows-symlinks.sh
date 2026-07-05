#!/usr/bin/env bash
# setup.sh の Windows (Git Bash/MSYS) symlink 対策の検証。
# - Git Bash の素の ln -s は symlink ではなくコピーを作るため、setup.sh は
#   MINGW/MSYS 検出時に MSYS=winsymlinks:nativestrict を export していること
# - .gitconfig.win の分岐が実際の uname (ビルド番号付き) にマッチすること
# - Windows では export 下の ln -sfn が本物の symlink を作ること (要: 開発者モード)
set -u
DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="${DOTDIR}/setup.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "ok: $1"; }
ng() { FAIL=$((FAIL+1)); echo "NG: $1"; }

# (1) MINGW/MSYS 向けの export が存在する
if grep -q 'export MSYS=winsymlinks:nativestrict' "$SETUP"; then
  ok "setup.sh exports MSYS=winsymlinks:nativestrict for MINGW/MSYS"
else
  ng "setup.sh lacks 'export MSYS=winsymlinks:nativestrict'"
fi

# (2) 壊れた uname 完全一致 (ビルド番号付き uname にマッチしない) が残っていない
if grep -qF '= MINGW64_NT-10.0 ]' "$SETUP"; then
  ng "setup.sh still compares uname to literal 'MINGW64_NT-10.0' (never matches e.g. $(uname -s))"
else
  ok "no broken exact-match uname comparison"
fi

# (3) Windows 実機: export 下の ln -sfn が本物の symlink を作る
case "$(uname -s)" in
  MINGW*|MSYS*)
    export MSYS=winsymlinks:nativestrict
    T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
    mkdir "$T/target"
    if ln -sfn "$T/target" "$T/link" 2>/dev/null && [ -L "$T/link" ]; then
      ok "ln -sfn creates a real symlink under winsymlinks:nativestrict"
    else
      ng "ln -sfn did not create a real symlink (developer mode off? admin required?)"
    fi
    ;;
  *)
    echo "skip: non-Windows host (symlink behavior test not applicable)"
    ;;
esac

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
