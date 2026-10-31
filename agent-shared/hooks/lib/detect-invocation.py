#!/usr/bin/env python3
"""PostToolUse hook (outward-write-readback.sh) 用: コマンド中の「実際の起動」を検出する。

使い方: detect-invocation.py [--shell powershell] NAME...
引数で渡した名前 (例: gh, git) の呼び出しを、以前の判定 (head_judge.py に凍結した b337715 の
detect-invocation.py。ヒアドキュメントの本文を除き、コマンドの位置にある呼び出しを集める近似の読み。push かどうかは
outward-write-readback.sh が呼び出しの語に正規表現を当てて照合する) と構文木の判定 (shell_commands.py) の和で拾う。
以前の判定が分割できないときは、ガードと同じく書き換えて読み直さず undecidable とし、閉じられない引用符の行
(元のコマンドの行) と文字を理由に書く。

stdin から hook の JSON を読む。出力の 1 行目は "ok" か "undecidable"、2 行目は通知文 (10 分に 1 回へ間引く。
無ければ空)。ok なら 3 行目以降に呼び出しを 1 行 1 件 (前置きの sudo / env 等を剥がしたトークン列を空白で連結)、
undecidable なら 3 行目が理由。トークン内の改行は空白にする。複数行の引数 (commit message 等) の中の行を
別の呼び出しと誤認しないため。

下の strip_heredocs / invocations は detect-wrapped-gh.py が使う以前の関数 (b337715 のまま)。
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import head_judge  # noqa: E402
import parser_tools  # noqa: E402
from shell_commands import (  # noqa: E402
    DEADLINE_SECONDS, Deadline, analyze, executable, head_split_where, setup_stdout, shell_argument, tool_command,
)

_HEAD = head_judge.legacy_module()
strip_heredocs = _HEAD["strip_heredocs"]
invocations = _HEAD["invocations"]


def main():
    setup_stdout()
    argv = sys.argv[1:]
    shell = shell_argument(argv)
    if "--shell" in argv:
        del argv[argv.index("--shell"):argv.index("--shell") + 2]
    names = sorted(set(argv))
    raw = sys.stdin.buffer.read()
    command = tool_command(raw)
    if not command:
        print("ok")
        print("")
        return 0
    deadline = Deadline(DEADLINE_SECONDS)
    head_calls = head_judge.detect_text(raw, names)
    if head_calls == "EPARSE":
        found = head_split_where("gh", command)
        where = found[0] if found else "閉じられない引用符 (位置は特定できなかった)"
        print("undecidable")
        print("")
        print(" ".join(f"以前の判定 (shlex による近似の読み。ヒアドキュメントの本文は読まない) が {where}ため、"
                       "呼び出しを分割できなかった".split()))
        return 0
    analysis = analyze(command, shell, deadline)
    tree_calls = [" ".join(" ".join(token.split()) for token in tokens)
                  for tokens in analysis.commands if executable(tokens[0]) in names]
    calls = [line for line in head_calls.split("\n") if line] + tree_calls
    notice = analysis.notice if analysis.notice and parser_tools.should_notify(analysis.notice) else ""
    print("ok")
    print(" ".join(notice.split()))
    for call in dict.fromkeys(calls):
        print(call)
    return 0


if __name__ == "__main__":
    sys.exit(main())
