#!/usr/bin/env python3
"""PreToolUse hook 用: gh が sandbox 内で走る形の呼び出しを検出する。

sandbox.excludedCommands の `gh:*` に一致するのは、トップレベルでコマンド位置に立つ gh だけ。
一致しないと sandbox 内で走り、macOS では keychain 遮断で「token is invalid」を誤報告する。

実測から得られた規則は 1 つ:

    ラッパの内側 (env / xargs / シェルの -c / サブシェル) に入った gh は例外なく sandbox 内で
    走る。安全なのはトップレベルでコマンド位置に立つ gh だけで、照合前に剥がされるラッパ
    (timeout / time / nice / stdbuf / nohup / command / builtin) の後ろもそこに含まれる。

そのため判定は「gh に到達する経路が、トップレベルの直呼び以外にあるか」に帰着する。形ごとの
場合分けを増やす代わりにこの規則を再帰で適用する。

字句解析は detect-invocation.py と共用する。単純な部分一致だと、コマンドを説明する文字列
(commit message や検索パターン) や `ssh -c` のような別コマンドの一部を起動と誤認する。
誤発火は「無意味な警告」として hook 全体を無視する習慣を作るため、そこは横着しない。

stdin から hook の JSON を読み、該当する呼び出しを 1 行 1 件で出力する。解析できない断片は
その断片だけ諦める (見つかっている検出は捨てない)。構文エラーで実行されない形 (閉じない
`$(` やバッククォート) は警告しない。**取りこぼしても後段は無い** — 事後に出力を見て誤診を
止める形 (PostToolUse hook) は、Bash が非 0 終了した呼び出しでは起動しないため成立しない。

既知の非カバー (いずれも黙って落ちる。警告が無い = 安全、ではない):
- ラッパが MAX_DEPTH 段を超えて入れ子になった形。実運用の深さ (`xargs` → シェル `-c` → `env`
  → gh で 3) には足りるが、それ以上は追わない。
- エイリアス経由・シェル関数経由 (コマンド文字列からは展開先が分からない)。
- `sudo gh` (未実測。除外に一致するかどうかを確かめていない)。
"""

import importlib.util
import json
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location(
    "detect_invocation", os.path.join(_HERE, "detect-invocation.py")
)
_DI = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_DI)

# 照合前に剥がされるラッパ。トップレベルではこの後ろの gh も除外に一致する
# (実測したのは nohup / command / nice。残りは実装がこれらを剥がすことによる)。
STRIP_WRAPPERS = {"timeout", "time", "nice", "stdbuf", "nohup", "command", "builtin"}
# -c でスクリプト文字列を受け取るシェル
SHELLS = {"bash", "sh", "zsh", "fish", "dash", "ksh"}
# 後続のトークンを別コマンドとして起動するラッパ
RUNNERS = {"env", "xargs"}
# 字句解析器に渡す名前。ここに無いコマンドは gh へ到達しない (到達経路を持たない)。
ALL_NAMES = {"gh"} | SHELLS | RUNNERS | STRIP_WRAPPERS

ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")

# 分離した次のトークンを引数として食うオプション。読み飛ばさないとコマンド語を取り違える。
# optional arg のもの (GNU xargs の -i / -l / -e、long form の --replace / --eof / --max-lines)
# は次のトークンを食わない (結合形で書く) ため入れない。BSD (macOS 既定) と GNU の両方を
# 混ぜて持つ — 登録漏れはコマンド語の取り違え = 取りこぼし = 誤診に直結する一方、
# 余分なエントリはその実装に現れないため無害、という非対称性による。
TAKES_ARG = {
    "env": {"-u", "--unset", "-C", "--chdir", "-P"},
    "xargs": {"-n", "--max-args", "-I", "-L", "-P", "--max-procs", "-a", "--arg-file",
              "-d", "--delimiter", "-E", "-s", "--max-chars", "-J", "-R", "-S"},
}

# シェルで分離した引数を取るオプション。short の結合形は 'o' を含むかで判定する
# (`bash -euo pipefail -c ...` の -euo が pipefail を食う)。
SHELL_LONG_TAKES_ARG = {"--rcfile", "--init-file", "--init-command"}
SHELL_SHORT_TAKES_ARG = "oC"

# 入れ子を追う深さ。循環しない構造なので打ち切り用。
MAX_DEPTH = 4


def basename(token):
    return token.rsplit("/", 1)[-1]


def subshell_fragments(command):
    """サブシェルで実行される断片を返す。`$(...)`・バッククォート・`<(...)`・`>(...)`。

    先にヒアドキュメント本文を落とす。commit message で gh の呼び出し形をバッククォートや
    `$()` で引用するのは日常的に起きるため、本文を残すと引用を起動と誤認する。
    `<<EOF` (クォートなし) の本文では実際には展開が起きるが、そちらを拾うために引用で
    誤発火する側を選ばない。

    引用符状態を追う。単引用符の中では置換が起きないので対象外、二重引用符の中では起きる。
    括弧の対応も引用符を見ながら数える (中の `(` や `)` が引用符に入っていると深さが狂い、
    切り出しが前後にずれて取りこぼしと誤検出の両方を起こす)。
    閉じていない形は構文エラーで実行されないため返さない。
    """
    command = _DI.strip_heredocs(command)
    out = []
    i = 0
    n = len(command)
    single = double = False

    while i < n:
        ch = command[i]
        if ch == "\\" and not single:
            i += 2
            continue
        if ch == "'" and not double:
            single = not single
        elif ch == '"' and not single:
            double = not double
        elif not single and (command.startswith("$(", i)
                             or command.startswith("<(", i)
                             or command.startswith(">(", i)):
            start = i + 2
            j = start
            depth = 1
            inner_single = inner_double = False
            while j < n and depth:
                c = command[j]
                if c == "\\" and not inner_single:
                    j += 2
                    continue
                if c == "'" and not inner_double:
                    inner_single = not inner_single
                elif c == '"' and not inner_single:
                    inner_double = not inner_double
                elif not inner_single and not inner_double:
                    if c == "(":
                        depth += 1
                    elif c == ")":
                        depth -= 1
                j += 1
            if depth == 0:
                out.append(command[start:j - 1])
            i = j
            continue
        elif not single and ch == "`":
            j = command.find("`", i + 1)
            if j < 0:
                break
            out.append(command[i + 1:j])
            i = j + 1
            continue
        i += 1

    return out


def shell_script_arg(args):
    """シェルの -c が受け取るスクリプト文字列。オプション領域だけを走査する。

    非オプションに達したらそこはスクリプトファイル名で、以降の -c はシェルではなく
    そのスクリプトの引数 (`bash script.sh -c '...'`)。long option は 1 文字フラグの
    集合ではないので、名前に c を含んでも (`--norc`) -c とは見なさない。
    """
    i = 0
    while i < len(args):
        token = args[i]
        if token == "--" or not (token.startswith("-") or token.startswith("+")):
            return None
        if token.startswith("--"):
            i += 2 if token in SHELL_LONG_TAKES_ARG else 1
            continue
        flags = token[1:]
        if "c" in flags:
            return args[i + 1] if i + 1 < len(args) else None
        i += 2 if any(f in SHELL_SHORT_TAKES_ARG for f in flags) else 1
    return None


def env_inline_script(args):
    """env -S / --split-string が受け取るコマンド行。無ければ None。"""
    for i, token in enumerate(args):
        if token in ("-S", "--split-string") and i + 1 < len(args):
            return args[i + 1]
        if token.startswith("--split-string="):
            return token.split("=", 1)[1]
        if token.startswith("-S") and len(token) > 2:
            return token[2:]
    return None


def runner_tail(name, args):
    """env / xargs のオプションと前置代入を読み飛ばした先のトークン列。"""
    takes_arg = TAKES_ARG.get(name, set())
    i = 0
    while i < len(args):
        token = args[i]
        if token == "--":
            i += 1
            break
        if ASSIGN.match(token):
            i += 1
            continue
        if token.startswith("-"):
            i += 2 if token in takes_arg else 1
            continue
        break
    return args[i:]


def wrapper_tail(args):
    """剥がされるラッパの後ろにある起動のトークン列。

    timeout の duration や nice の -n 5 のように位置引数を取るものがあるため、
    オプション判定ではなく「到達経路を持つ名前」が現れる位置から先を返す。
    """
    for i, token in enumerate(args):
        if basename(token) in ALL_NAMES:
            return args[i:]
    return []


def tokens_reach_gh(tokens, depth):
    """ラッパの内側として与えられたトークン列が gh に到達するか。内側は常に sandbox 内。"""
    if depth > MAX_DEPTH or not tokens:
        return False

    name = basename(tokens[0])
    args = tokens[1:]

    if name == "gh":
        return True
    if name in STRIP_WRAPPERS:
        return tokens_reach_gh(wrapper_tail(args), depth + 1)
    if name in SHELLS:
        script = shell_script_arg(args)
        return script is not None and text_reaches_gh(script, depth + 1)
    if name in RUNNERS:
        script = env_inline_script(args) if name == "env" else None
        if script is not None:
            return text_reaches_gh(script, depth + 1)
        return tokens_reach_gh(runner_tail(name, args), depth + 1)
    return False


def text_reaches_gh(text, depth):
    """コマンド文字列が gh に到達するか。この文字列自体が既に sandbox 内にある前提。"""
    if depth > MAX_DEPTH:
        return False

    try:
        invocations = _DI.invocations(text, ALL_NAMES)
    except ValueError:
        invocations = []

    for tokens in invocations:
        if tokens_reach_gh(tokens, depth):
            return True

    return any(text_reaches_gh(fragment, depth + 1)
               for fragment in subshell_fragments(text))


def wrapped_gh_calls(command):
    """sandbox 内で gh が走る呼び出しを返す。トップレベルの直呼びは除外に一致するので返さない。"""
    found = []

    try:
        invocations = _DI.invocations(command, ALL_NAMES)
    except ValueError:
        invocations = []

    for tokens in invocations:
        name = basename(tokens[0])

        if name == "gh":
            continue

        if name in STRIP_WRAPPERS:
            tail = wrapper_tail(tokens[1:])
            # 剥がされた先が gh 自身なら除外に一致する。別のラッパならその内側は sandbox 内。
            if tail and basename(tail[0]) != "gh" and tokens_reach_gh(tail, 1):
                found.append(tokens)
            continue

        if tokens_reach_gh(tokens, 0):
            found.append(tokens)

    for fragment in subshell_fragments(command):
        if text_reaches_gh(fragment, 1):
            found.append(["$(" + " ".join(fragment.split()) + ")"])

    return found


def main():
    try:
        command = json.load(sys.stdin).get("tool_input", {}).get("command", "")
    except Exception:
        return 0

    if not isinstance(command, str) or not command:
        return 0

    for tokens in wrapped_gh_calls(command):
        print(" ".join(tokens))

    return 0


if __name__ == "__main__":
    sys.exit(main())
