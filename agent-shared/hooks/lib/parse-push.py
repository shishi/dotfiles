#!/usr/bin/env python3
"""git push の呼び出しから、確認すべき作業ディレクトリ・送信元 ref・宛先ブランチを取り出す。

readback hook が「どのリポジトリの、どのブランチを、何と突き合わせるか」を誤ると、
成功した push に対して警告を出す。誤警報は hook を無視する習慣を作るので、
実際の push が何を指しているかに忠実に解釈する。

- git -C <dir> … 別のワークツリーへの push。そのディレクトリで確認する
- git push <remote> <src>:<dst> … 宛先は dst
- git push <remote> <branch> … src も dst も branch
- 引数なし … 現在のブランチ

stdin から `git ... push ...` のトークン列 (1 行) を読み、
dir, remote, src, dst を 1 行ずつ出力する。空行は既定値の意味。

区切りにタブを使わないこと。bash の read はタブを IFS 空白として扱うため、
先頭の空フィールドが消えて代入先が 1 つずつずれる。
"""

import sys

FLAGS_WITH_VALUE = {"-o", "--push-option", "--receive-pack", "--exec", "--repo"}


def parse(tokens):
    directory = ""
    index = 0

    # git 直後のグローバルオプション
    while index < len(tokens):
        token = tokens[index]
        if token == "-C" and index + 1 < len(tokens):
            directory = tokens[index + 1]
            index += 2
            continue
        if token == "push":
            index += 1
            break
        index += 1

    remote = ""
    refspecs = []
    while index < len(tokens):
        token = tokens[index]
        if token in FLAGS_WITH_VALUE:
            index += 2
            continue
        if token.startswith("-"):
            index += 1
            continue
        if not remote:
            remote = token
        else:
            refspecs.append(token)
        index += 1

    src = dst = ""
    if refspecs:
        head = refspecs[0].lstrip("+")
        if ":" in head:
            src, dst = head.split(":", 1)
        else:
            src = dst = head

    # 宛先は「ブランチ名」に正規化する。呼び出し側が refs/heads/ を付け直すため、
    # ここで残すと refs/heads/refs/heads/... になって必ず不在判定になる。
    if dst.startswith("refs/heads/"):
        dst = dst[len("refs/heads/"):]

    return directory, remote or "origin", src, dst


def main():
    line = sys.stdin.read().strip()
    if not line:
        return 0
    for field in parse(line.split()):
        print(field)
    return 0


if __name__ == "__main__":
    sys.exit(main())
