"""この変更の前 (b337715) のガードの判定を、そのまま凍結して呼ぶ。

下の HEAD_* は b337715 の該当箇所 (reboot-guard.sh・control-loss-guard.sh・gh-body-file-guard.sh の
python -c に渡していた文字列と、lib/detect-invocation.py の全文) を 1 文字も変えずに写したもの。
新しい構文木の判定 (shell_commands.py) とは関数を共有しない。新しいガードの判定はこの結果を必ず含む
(以前の判定が止めていたものは止める)。lib/head-judge-cases.py が b337715 の本文と一致することを照合する。

各プログラムは以前と同じく、標準入力と終了コードでやり取りする。ここでは別プロセスを立てずに、
同じプロセスの中で標準入出力を差し替えて実行する。入力は jq が出す UTF-8 のバイト列にし、旧シェルの $(...) と
同じく NUL と末尾の改行を除いてから、この環境の既定の符号化 (以前の python -c が読んだのと同じ) で読ませる。
"""

import io
import os
import json
import re
import sys

HEAD_REBOOT = r'''import os
import shlex
import sys

src = sys.stdin.read()
separators = {";", "|", "||", "&", "&&", "(", ")"}

def executable(token):
    return os.path.basename(token.replace("\\", "/")).removesuffix(".exe").lower()

def strip_assignments(tokens):
    while tokens and "=" in tokens[0] and tokens[0].split("=", 1)[0].replace("_", "").isalnum():
        tokens = tokens[1:]
    return tokens

def unwrap(tokens):
    tokens = strip_assignments(tokens)
    while tokens:
        command_name = executable(tokens[0])
        if command_name in {"sudo", "doas"}:
            value_options = {"-u", "--user", "-g", "--group", "-h", "--host", "-p", "--prompt"}
            index = 1
            while index < len(tokens):
                option = tokens[index]
                if option == "--":
                    index += 1
                    break
                if option in value_options:
                    index += 2
                    continue
                if option.startswith("-"):
                    index += 1
                    continue
                break
            tokens = strip_assignments(tokens[index:])
            continue
        if command_name == "env":
            index = 1
            while index < len(tokens) and (tokens[index].startswith("-") or "=" in tokens[index]):
                index += 1
            tokens = strip_assignments(tokens[index:])
            continue
        if command_name in {"command", "nohup"}:
            index = 1
            while index < len(tokens) and tokens[index].startswith("-"):
                index += 1
            tokens = strip_assignments(tokens[index:])
            continue
        break
    return tokens

def contains_reboot(command, depth=0):
    if depth > 3:
        return True
    nested = command.replace("\n", " ; ")
    lexer = shlex.shlex(nested, posix=True, punctuation_chars="();|&")
    lexer.whitespace_split = True
    nested_tokens = list(lexer)
    nested_segments = []
    current = []
    for token in nested_tokens:
        if token in separators:
            if current:
                nested_segments.append(current)
                current = []
        else:
            current.append(token)
    if current:
        nested_segments.append(current)

    for segment in nested_segments:
        segment = unwrap(segment)
        if not segment:
            continue
        command_name = executable(segment[0])
        arguments = [argument.lower() for argument in segment[1:]]
        if command_name in {"reboot", "restart-computer"}:
            return True
        if command_name in {"systemctl", "loginctl"} and any(argument in {"reboot", "soft-reboot"} for argument in arguments):
            return True
        if command_name == "shutdown" and any(argument in {"-r", "/r", "--reboot"} for argument in arguments):
            return True
        if command_name in {"bash", "sh", "zsh"}:
            for index, option in enumerate(segment[1:], start=1):
                if option.startswith("-") and "c" in option[1:] and index + 1 < len(segment):
                    if contains_reboot(segment[index + 1], depth + 1):
                        return True
                    break
    return False

try:
    if contains_reboot(src):
        sys.exit(0)
except ValueError:
    sys.exit(2)
sys.exit(1)
'''

HEAD_CONTROL_LOSS = r'''import os
import shlex
import sys

src = sys.stdin.read()
separators = {";", "|", "||", "&", "&&", "(", ")"}

def executable(token):
    return os.path.basename(token.replace("\\", "/")).removesuffix(".exe").lower()

def strip_assignments(tokens):
    while tokens and "=" in tokens[0] and tokens[0].split("=", 1)[0].replace("_", "").isalnum():
        tokens = tokens[1:]
    return tokens

def unwrap(tokens):
    tokens = strip_assignments(tokens)
    while tokens:
        name = executable(tokens[0])
        if name in {"sudo", "doas"}:
            value_options = {"-u", "--user", "-g", "--group", "-h", "--host", "-p", "--prompt"}
            index = 1
            while index < len(tokens):
                option = tokens[index]
                if option == "--":
                    index += 1
                    break
                if option in value_options:
                    index += 2
                    continue
                if option.startswith("-"):
                    index += 1
                    continue
                break
            tokens = strip_assignments(tokens[index:])
            continue
        if name == "env":
            index = 1
            while index < len(tokens) and (tokens[index].startswith("-") or "=" in tokens[index]):
                index += 1
            tokens = strip_assignments(tokens[index:])
            continue
        if name in {"command", "nohup"}:
            index = 1
            while index < len(tokens) and tokens[index].startswith("-"):
                index += 1
            tokens = strip_assignments(tokens[index:])
            continue
        break
    return tokens

def classify(command, depth=0):
    if depth > 3:
        return "unknown"
    lexer = shlex.shlex(command.replace("\n", " ; "), posix=True, punctuation_chars="();|&")
    lexer.whitespace_split = True
    segments, current = [], []
    for token in list(lexer):
        if token in separators:
            if current:
                segments.append(current)
                current = []
        else:
            current.append(token)
    if current:
        segments.append(current)

    for segment in segments:
        segment = unwrap(segment)
        if not segment:
            continue
        name = executable(segment[0])
        args = [arg.lower() for arg in segment[1:]]
        if name == "adb" and ("reboot" in args or args[:2] == ["emu", "kill"]):
            return "emulator"
        if name == "loginctl" and any(arg in {"lock-session", "terminate-session", "terminate-user"} for arg in args):
            return "session"
        if name == "systemctl":
            actions = {"stop", "restart", "try-restart", "isolate"}
            session_units = {"display-manager", "sddm", "gdm", "lightdm", "rustdesk", "sshd"}
            network_units = {"networkmanager", "tailscaled"}
            units = {arg.removesuffix(".service") for arg in args}
            if actions.intersection(args) and session_units.intersection(units):
                return "session"
            if actions.intersection(args) and network_units.intersection(units):
                return "network"
        if name == "nmcli" and (args[:2] == ["networking", "off"] or args[:3] == ["radio", "all", "off"]):
            return "network"
        if name == "tailscale" and args[:1] == ["down"]:
            return "network"
        if name == "ip" and "link" in args and "down" in args:
            return "network"
        if name in {"bash", "sh", "zsh"}:
            for index, option in enumerate(segment[1:], start=1):
                if option.startswith("-") and "c" in option[1:] and index + 1 < len(segment):
                    nested = classify(segment[index + 1], depth + 1)
                    if nested:
                        return nested
                    break
    return ""

try:
    kind = classify(src)
except ValueError:
    sys.exit(2)
if kind:
    print(kind)
    sys.exit(0)
sys.exit(1)
'''

HEAD_GH_OFFENDER = r'''import re, sys

for line in sys.stdin:
    if not re.match(r"\Agh\s+(pr|issue|release)\b", line.strip()):
        continue
    for opt in ("--body-file", "--notes-file", "--template"):
        m = re.search(re.escape(opt) + r"\s+(\S+)", line)
        if m and m.group(1) != "-":
            print(f"{opt} {m.group(1)}")
            sys.exit(0)
'''

HEAD_DETECT_INVOCATION = r'''#!/usr/bin/env python3
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
    sys.stdout.reconfigure(newline="\n")
    names = set(sys.argv[1:])
    try:
        tool_input = json.load(sys.stdin).get("tool_input", {})
        command = tool_input.get("command") or tool_input.get("cmd", "")
    except Exception:
        return 0

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
'''


# 以前の python -c は標準入出力をこの環境の既定の符号化 (Windows では cp932、UTF-8 モードなら UTF-8) で読み書きしていた。
# 同じ環境のこのプロセスが起動したときの符号化を使う (setup_stdout が標準出力を UTF-8 に変える前に取っておく)。
STDIN_ENCODING = getattr(sys.__stdin__, "encoding", None) or "utf-8"
STDIN_ERRORS = getattr(sys.__stdin__, "errors", None) or "strict"
STDOUT_ENCODING = getattr(sys.__stdout__, "encoding", None) or "utf-8"
STDOUT_ERRORS = getattr(sys.__stdout__, "errors", None) or "strict"
SURROGATE = re.compile("[\ud800-\udfff]")


def _run(source, stdin_bytes, argv=()):
    """source を __main__ として実行し、(終了コード, 標準出力のバイト列) を返す。"""
    saved = sys.stdin, sys.stdout, sys.argv
    stdout = io.TextIOWrapper(io.BytesIO(), encoding=STDOUT_ENCODING, errors=STDOUT_ERRORS)
    # 以前の python -c の標準入力が改行を変換するのは Windows だけ (POSIX では \r をそのまま読む)
    sys.stdin = io.TextIOWrapper(io.BytesIO(stdin_bytes), encoding=STDIN_ENCODING, errors=STDIN_ERRORS,
                                 newline=None if os.name == "nt" else "\n")
    sys.stdout = stdout
    sys.argv = ["head_judge", *argv]
    code = 0
    try:
        exec(compile(source, "<b337715>", "exec"), {"__name__": "__main__"})
    except SystemExit as exit_:
        code = exit_.code if isinstance(exit_.code, int) else (0 if exit_.code is None else 1)
    except Exception:  # noqa: BLE001 - 以前の python と同じく、捕まえていない例外は終了コード 1
        code = 1
    finally:
        sys.stdin, sys.stdout, sys.argv = saved
    try:
        stdout.flush()
    except Exception:  # noqa: BLE001 - 符号化できない文字を書いた等。以前も出力は途中までになる
        pass
    return code, stdout.buffer.getvalue()


def shell_bytes(data):
    """bash の $(...) と同じく、NUL を除き末尾の改行を除く。"""
    return data.replace(b"\x00", b"").rstrip(b"\n")


def jq_bytes(text):
    """jq -r が出す UTF-8 のバイト列 (単独のサロゲートは U+FFFD に置き換わる)。"""
    return SURROGATE.sub("�", text).encode("utf-8")


def hook_command(raw):
    """以前のガードが jq -r '.tool_input.command // empty' で取り出していた値 (文字列)。"""
    try:
        value = (json.loads(raw.decode("utf-8", "surrogateescape")).get("tool_input") or {}).get("command")
    except (ValueError, AttributeError):
        return ""
    if value is None or value is False:
        return ""
    return value if isinstance(value, str) else json.dumps(value, indent=2, ensure_ascii=False)


def reboot(command):
    """("match", "reboot") / ("none", "") / ("undecidable", "")。以前の reboot-guard.sh と同じ判定。"""
    data = shell_bytes(jq_bytes(command))
    if not data:
        return ("none", "")
    code, _ = _run(HEAD_REBOOT, data)
    return {0: ("match", "reboot"), 1: ("none", "")}.get(code, ("undecidable", ""))


def control_loss(command):
    """("match", 種類) / ("none", "") / ("undecidable", "")。入れ子が 4 段を超えたときの種類は unknown (以前どおり止める)。"""
    data = shell_bytes(jq_bytes(command))
    if not data:
        return ("none", "")
    code, out = _run(HEAD_CONTROL_LOSS, data)
    if code == 0:
        return ("match", out.decode(STDOUT_ENCODING, "replace").strip())
    return ("none", "") if code == 1 else ("undecidable", "")


def detect(raw, names):
    """以前の detect-invocation.py の出力 (バイト列。呼び出しを 1 行 1 件、分割できなければ EPARSE)。

    以前のガードは hook 入力を input=$(cat) で受け、出力も $(...) で受けていたので、どちらも NUL を除く。
    """
    return shell_bytes(_run(HEAD_DETECT_INVOCATION, shell_bytes(raw), names)[1])


def detect_text(raw, names):
    return detect(raw, names).decode(STDOUT_ENCODING, "replace")


def gh(raw):
    """("match", "--body-file x") / ("none", "") / ("undecidable", "")。以前の gh-body-file-guard.sh と同じ判定。"""
    calls = detect(raw, ["gh"])
    if not calls:
        return ("none", "")
    if calls == b"EPARSE":
        return ("undecidable", "")
    offender = shell_bytes(_run(HEAD_GH_OFFENDER, calls)[1]).decode(STDOUT_ENCODING, "replace")
    return ("match", offender) if offender else ("none", "")


def hook_input_with(command):
    """command だけを持つ hook 入力 (検出をやり直すとき用)。"""
    return json.dumps({"tool_input": {"command": command}}, ensure_ascii=False).encode("utf-8")


def legacy_module():
    """以前の detect-invocation.py の関数 (strip_heredocs・invocations)。detect-wrapped-gh.py が使う。"""
    namespace = {"__name__": "head_detect_invocation"}
    exec(compile(HEAD_DETECT_INVOCATION, "<b337715 detect-invocation.py>", "exec"), namespace)
    return namespace
