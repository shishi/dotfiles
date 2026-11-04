#!/usr/bin/env python3
"""PreToolUse / PostToolUse hook 共通: Bash コマンド中の「実際の起動」を検出する。

引数で渡した名前 (例: gh, git) が *コマンド位置* に現れる呼び出しだけを拾い、
その呼び出しのトークン列を 1 行 1 件で出力する。

コマンド位置とは、コマンド列の先頭、または改行・; ・パイプ・&& などの区切りの直後を指す。
クォートやヒアドキュメント本文に同じ文字列が現れても、そこはコマンド位置ではないため拾わない。
単純な部分一致だと、コマンドを説明する文字列や JSON ペイロードを起動と誤認して誤発火する。

改行の扱いに注意がいる。shlex は改行を空白として扱うため、素通しにすると 2 行目以降が
コマンド位置と認識されず、複数行コマンドの検出をまるごと取りこぼす。改行は区切りへ変換する。
その前にヒアドキュメント本文を取り除く。本文はコマンドではないうえ、改行を区切りに変えると
本文の各行が起動に見えてしまうため。

stdin から hook の JSON を読み、tool_input.command または tool_input.cmd を対象にする。
クォートが閉じていない等で解析できない場合は EPARSE 行で伝える
(呼び出し側が保守的に倒せるようにするため、無音にはしない)。
"""

import json
import re
import shlex
import sys

SEPARATORS = {";", "|", "||", "&", "&&", "(", ")", "{", "}"}
HEREDOC = re.compile(r"<<(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")


def strip_heredocs(command):
    """ヒアドキュメント本文を取り除く。"""
    lines = command.split("\n")
    kept = []
    pending = []

    for line in lines:
        if pending:
            marker, allow_indent = pending[0]
            candidate = line.strip() if allow_indent else line.rstrip()
            if candidate == marker:
                pending.pop(0)
            continue

        kept.append(line)
        for match in HEREDOC.finditer(line):
            pending.append((match.group(3), bool(match.group(1))))

    return "\n".join(kept)


def invocations(command, names):
    """コマンド位置に names のいずれかが現れる呼び出しを、トークン列のリストで返す。"""
    command = strip_heredocs(command).replace("\n", " ; ")

    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True

    found = []
    at_command_position = True
    current = None

    for token in lexer:
        if token in SEPARATORS:
            at_command_position = True
            current = None
            continue

        if at_command_position:
            # VAR=value は前置代入なのでコマンド位置のまま進む
            head = token.split("=", 1)[0]
            if "=" in token and head and head.replace("_", "").isalnum():
                continue
            at_command_position = False
            if token in names or token.rsplit("/", 1)[-1] in names:
                current = [token]
                found.append(current)
            continue

        if current is not None:
            current.append(token)

    return found


def main():
    # Windows の Python は改行を CRLF で書き、行単位で読むシェル側の値に CR が残る。
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    names = set(sys.argv[1:])
    # hook の JSON は UTF-8。既定の符号化 (Windows では cp932 等) で読むと日本語を含む入力で失敗するため、
    # バイト列から読む。読めないときは黙って「呼び出しなし」にせず、失敗として呼び出し側へ返す。
    try:
        tool_input = json.loads(sys.stdin.buffer.read()).get("tool_input", {})
        command = tool_input.get("command") or tool_input.get("cmd", "")
        # Codex は argv 配列で渡すことがある。1 行のコマンドとして読む。
        if isinstance(command, list):
            command = shlex.join(map(str, command))
        if not isinstance(command, str):
            raise TypeError(f"command が文字列でも配列でもない ({type(command).__name__})")
    except Exception as error:
        print(f"hook の入力を読めなかった: {error}", file=sys.stderr)
        return 2

    if not command:
        return 0

    try:
        for tokens in invocations(command, names):
            print(" ".join(tokens))
    except ValueError:
        print("EPARSE")

    return 0


if __name__ == "__main__":
    sys.exit(main())
