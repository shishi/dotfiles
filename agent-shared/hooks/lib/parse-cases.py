"""parse-push.py の解釈テスト。dir / remote / src / dst を突き合わせる。"""

import os
import subprocess
import sys

PARSER = os.path.expanduser("~/.claude/hooks/lib/parse-push.py")

# (説明, 呼び出し, 期待する dir, remote, src, dst)
CASES = [
    ("引数なし", "git push", "", "origin", "", ""),
    ("upstream 指定", "git push -u origin develop/foo", "", "origin", "develop/foo", "develop/foo"),
    ("別ワークツリー", "git -C /tmp/wt push", "/tmp/wt", "origin", "", ""),
    ("別ワークツリー + ブランチ",
     "git -C /tmp/wt push origin develop/foo", "/tmp/wt", "origin", "develop/foo", "develop/foo"),
    ("refspec で宛先が異なる (refs/heads/ は剥がす)",
     "git push origin HEAD:refs/heads/develop/bar", "", "origin", "HEAD", "develop/bar"),
    ("別リモート", "git push upstream main", "", "upstream", "main", "main"),
    ("フラグ混在", "git push --quiet -u origin develop/foo", "", "origin", "develop/foo", "develop/foo"),
]


def main():
    failed = 0
    for label, call, *expected in CASES:
        out = subprocess.run(["python3", PARSER], input=call, capture_output=True,
                             text=True, timeout=30).stdout
        actual = out.split("\n")[:4]
        ok = actual == expected
        failed += 0 if ok else 1
        print(f"{'PASS' if ok else 'FAIL'}  {label}: {actual}" + ("" if ok else f"  期待={expected}"))
    print(f"\n{len(CASES)} cases, {failed} failures")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
