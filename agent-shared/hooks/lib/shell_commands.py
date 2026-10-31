r"""ガードの判定 (PreToolUse / PostToolUse hook 共通)。以前の判定 (head_judge.py に凍結) と構文木の判定を合わせる。

合成 (guard_main・detect-invocation.py):
1. 以前の判定 (b337715 の判定をそのまま実行) が対象を見つけたら止める。
2. 以前の判定がコマンドを分割できない (shlex が引用符の対応を取れない) ときも、以前と同じく止める。コマンドを
   書き換えて読み直すことはしない。理由には、以前の判定が閉じられなかった引用符の行と文字、避け方を書く
   (head_split_failure。行は元のコマンドの行で数える)。
3. 以前の判定に対象が無いとき、構文木の判定が対象を見つけたら止める。以前の判定が見逃す形 (下の木の機能) を塞ぐ分。
4. それ以外は通す。

以前の判定が止めるもの (分割できないものを含む) はすべて止める。構文木は止めるものを足すだけ。

構文解析は本物の解析器に任せる。
- bash: shfmt (mvdan/sh) の `--to-json`。標準入力で渡すので一時ファイルは使わない。
- PowerShell: pwsh 7 (無ければ powershell.exe 5.1) の `Parser::ParseInput` (ps-commands.ps1)。

構文木で読む形と、以前の判定が見逃していた (以前は通し、今は止める) ことを示すテスト
(R: reboot-guard.test.sh、C: control-loss-guard.test.sh、H: lib/hook-cases.py の gh):
- 起動されるコマンドを木全体から集める。二重引用の中のコマンド置換 (R「二重引用内のコマンド置換」、
  C「コマンド置換の中」)、bash 5.3 の ${ cmd; } (R「bash 5.3 の ${ cmd; }」)、URL の # の後ろ
  (R「URL の # の後ろ」)、$'…' や行継続でつないだ語 (R「ANSI-C 引用で連結した語」「行継続で分けた語」)。
- "${x:-'$(cmd)'}" の ' は二重引用の中では引用にならない (R「二重引用内の ${x:-'$(...)'}」)。
- 未引用のヒアドキュメントの $(...) は外側のシェルが展開する (R「未引用のヒアドキュメントの外側の展開」、
  H「未引用のヒアドキュメントの $(...) は外側が実行する」)。
- 本文をシェルがスクリプトとして読むヒアドキュメント。以前の gh の判定は本文を除き、以前の再起動の判定は本文の
  行を 1 行ずつ近似で読む。受け手は引数なしの bash/sh/zsh・-s・/dev/stdin、source /dev/stdin、`cat <<EOF | bash`
  (H「bash へ流すヒアドキュメント」「bash -s へ…」「bash /dev/stdin へ…」「source /dev/stdin へ…」
  「cat からパイプで bash へ流す本文」、R「bash -s へ流す本文の二重引用内の置換」など)。
- 前置きを剥がす: sudo・doas の値を取るオプション (R「sudo -T の値」)、env -S (R「env -S」、H「env -S で分割した gh」)、
  su -c (R「su -c」)、timeout (R)、nix develop/shell -c (R・C)、docker/podman exec (R)、pkexec (R)、setsid (R)、
  wsl (R)。env - と command・nohup は以前の判定と同じ扱い (R「以前の判定で対象あり: env -」)。
- 文字列を別のシェルで実行する引数を同じ手順で読み直す: シェルの -c -- (R「bash -c -- の後」)、eval (R)、trap (R)、
  ssh の遠隔コマンド (R)、pwsh -EncodedCommand (R)、powershell.exe の位置引数 (R)、Invoke-Expression の引数
  (R「PowerShell: iex の引数」)、cmd /c (R「PowerShell: cmd /c の引数」。cmd の構文を bash として近似)。
- Start-Process の FilePath と、引用した 1 つの文字列の ArgumentList (R「PowerShell: Start-Process の ArgumentList」)。
- --shell powershell (Codex on Windows) では外側を bash としても読む (R「PowerShell: 外側を bash として読むと
  実行する形」)。hook 入力にシェルの種別が無く、Codex は呼び出しごとに shell を選べるため。
構文エラーのテキストは構文木では読まない (以前の判定が別に全体を読む)。
"""

import base64
import json
import os
import re
import shlex
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import head_judge
import parser_tools

SHELLS = {"bash", "sh", "zsh"}
POWERSHELLS = {"pwsh", "powershell"}
MAX_DEPTH = 6
MAX_SCRIPTS = 64
PARALLEL = 8


class ScriptSyntaxError(Exception):
    """解析器が構文エラーを返した。args[0] は解析器の行番号つきメッセージ。"""


# ---- コマンド語の扱い ----

def executable(token):
    return os.path.basename(token.replace("\\", "/")).lower().removesuffix(".exe")

ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=")

def strip_assignments(tokens):
    while tokens and ASSIGNMENT.match(tokens[0]):
        tokens = tokens[1:]
    return tokens

def _skip_options(tokens, takes_value):
    index = 1
    while index < len(tokens):
        option = tokens[index]
        if option == "--":
            return index + 1
        if option in takes_value:
            index += 2
            continue
        if option.startswith("-") and option != "-":
            index += 1
            continue
        break
    return index

def split_like_env(value):
    """env -S の分割規則 (空白区切り・引用・\\ の退避) で文字列を語に分ける。"""
    try:
        return shlex.split(value)
    except ValueError:
        return value.split()

SUDO_VALUE_OPTIONS = {"-u", "--user", "-g", "--group", "-h", "--host", "-p", "--prompt", "-C", "--close-from",
                      "-D", "--chdir", "-r", "--role", "-t", "--type", "-U", "--other-user",
                      "-T", "--command-timeout", "-R", "--chroot"}

def strip_env_words(tokens):
    """env・sudo の後の NAME=VALUE。env の仕様どおり、- で始まらず = を含む語は全部飛ばす。"""
    while tokens and "=" in tokens[0] and not tokens[0].startswith("-"):
        tokens = tokens[1:]
    return tokens

def _unwrap_sudo(tokens):
    """sudo / doas の前置きを剥がす。"""
    takes_value = {"-u"} if executable(tokens[0]) == "doas" else SUDO_VALUE_OPTIONS
    index = 1
    while index < len(tokens):
        option = tokens[index]
        if option == "--":
            index += 1
            break
        if option in takes_value:
            index += 2
            continue
        if option.startswith("-") and not option.startswith("--") and len(option) > 1:
            # 短いオプションの連結 (-Tu root)。値を取る文字が最後なら、値は次の語
            letters = option[1:]
            value_at = next((i for i, letter in enumerate(letters) if f"-{letter}" in takes_value), None)
            if value_at is not None and value_at == len(letters) - 1:
                index += 1
        elif not option.startswith("-"):
            break
        index += 1
    return strip_env_words(tokens[index:])

def _unwrap_env(tokens):
    index, split = 1, None
    while index < len(tokens):
        option = tokens[index]
        if option == "--":
            index += 1
            break
        if option in {"-S", "--split-string"}:
            split = tokens[index + 1] if index + 1 < len(tokens) else ""
            index += 2
            break
        if option.startswith("--split-string="):
            split = option.split("=", 1)[1]
            index += 1
            break
        if option.startswith("-S") and not option.startswith("--"):
            split = option[2:]
            index += 1
            break
        if option in {"-u", "--unset", "-C", "--chdir"}:
            index += 2
            continue
        if option.startswith("-") or "=" in option:
            index += 1  # `env -` は `env -i` と同じ (環境を空にする)。= を含む語は環境変数の指定
            continue
        break
    rest = tokens[index:]
    if split is not None:
        rest = split_like_env(split) + rest  # env -S は文字列を分割して、残りの引数の前に置く
    return strip_env_words(rest)

def _unwrap_su(tokens):
    """su -c のコマンドを sh -c として返す。-c が無ければそのまま (su の引数はコマンドではない)。"""
    index = 1
    while index < len(tokens):
        option = tokens[index]
        if option in {"-c", "--command"}:
            return ["sh", "-c", tokens[index + 1]] if index + 1 < len(tokens) else ["sh"]
        if option.startswith("--command="):
            return ["sh", "-c", option.split("=", 1)[1]]
        if option in {"-s", "--shell", "-g", "--group", "-G", "--supp-group", "-w", "--whitelist-environment"}:
            index += 2
            continue
        index += 1
    return tokens


def _skip_values(tokens, index, takes_value):
    """index からオプションを飛ばし、最初のオプションでない語の位置を返す。"""
    while index < len(tokens):
        option = tokens[index]
        if option == "--":
            return index + 1
        if option in takes_value:
            index += 2
            continue
        if option.startswith("-") and option != "-":
            index += 1
            continue
        break
    return index


DOCKER_VALUE_OPTIONS = {"-e", "--env", "-u", "--user", "-w", "--workdir", "--env-file", "--detach-keys"}
WSL_VALUE_OPTIONS = {"-d", "--distribution", "-u", "--user", "--cd", "--shell-type"}


def unwrap(tokens):
    """sudo / env / exec などの前置きを剥がし、実際に起動されるコマンドから始まる列を返す。"""
    tokens = strip_assignments(list(tokens))
    while tokens:
        name = executable(tokens[0])
        if name in {"sudo", "doas"}:
            tokens = _unwrap_sudo(tokens)
            continue
        if name == "env":
            tokens = _unwrap_env(tokens)
            continue
        if name == "su":
            unwrapped = _unwrap_su(tokens)
            if unwrapped is tokens:
                break
            return unwrapped
        if name == "command":
            if any(option in {"-v", "-V"} for option in tokens[1:2]):
                return []  # 実行せず所在を表示するだけ
            index = _skip_options(tokens, set())
        elif name == "nohup":
            index = _skip_options(tokens, set())
        elif name == "timeout":
            index = _skip_options(tokens, {"-s", "--signal", "-k", "--kill-after"}) + 1
        elif name == "nix" and tokens[1:2] in (["develop"], ["shell"]):
            index = next((i + 1 for i, token in enumerate(tokens) if token in {"-c", "--command"}), len(tokens))
        elif name in {"docker", "podman"} and tokens[1:2] == ["exec"]:
            index = _skip_values(tokens, 2, DOCKER_VALUE_OPTIONS) + 1  # オプションの後はコンテナ名、その後がコマンド
        elif name == "pkexec":
            index = _skip_options(tokens, {"--user"})
        elif name == "setsid":
            index = _skip_options(tokens, set())
        elif name == "wsl":
            index = _skip_values(tokens, 1, WSL_VALUE_OPTIONS)
        else:
            break
        tokens = strip_assignments(tokens[index:])
    return tokens


PS_VALUE_OPTIONS = ("executionpolicy", "windowstyle", "outputformat", "inputformat", "workingdirectory",
                    "configurationname", "version", "settingsfile", "custompipename", "psconsolefile")

PS_VALUE_ALIASES = {"ep", "ex", "w", "of", "o", "if", "i", "wd", "v"}

def powershell_script_source(tokens):
    """pwsh / powershell の起動で、-Command / -EncodedCommand / 位置引数として実行する文字列 (無ければ None)。"""
    if not tokens or executable(tokens[0]) not in POWERSHELLS:
        return None
    windows_powershell = executable(tokens[0]) == "powershell"
    index = 1
    while index < len(tokens):
        option = tokens[index]
        if option[:1] not in {"-", "/"} or len(option) < 2:
            break
        name = option[1:].lower().split(":", 1)[0]
        if name in {"c", "command"} or (len(name) >= 3 and "command".startswith(name)):
            rest = tokens[index + 1:]
            return " ".join(rest) if rest and rest != ["-"] else None
        if name in {"e", "ec", "enc"} or (len(name) >= 3 and "encodedcommand".startswith(name)):
            if index + 1 >= len(tokens):
                return None
            try:
                return base64.b64decode(tokens[index + 1]).decode("utf-16-le")
            except ValueError:
                return tokens[index + 1]
        if name in {"f", "file"} or (len(name) >= 2 and "file".startswith(name)):
            return None
        if name in PS_VALUE_ALIASES or any(len(name) >= 2 and full.startswith(name) for full in PS_VALUE_OPTIONS):
            index += 2
            continue
        index += 1
    rest = tokens[index:]
    if rest and windows_powershell:
        return " ".join(rest)  # powershell.exe は位置引数を -Command として扱う
    return None

def invoke_expression_text(tokens):
    """Invoke-Expression / iex の本文。引数が無ければ None (パイプ入力を使う)。"""
    arguments = []
    for token in tokens[1:]:
        lower = token.lower()
        if lower.startswith("-") and len(lower) > 1 and "command".startswith(lower[1:].split(":", 1)[0]):
            continue  # -Command とその短縮 (-c, -co, ...)。値は次の語
        arguments.append(token)
    return " ".join(arguments) if arguments else None

SSH_TAKES_VALUE = set("BbcDEeFIiJLlmOoPpQRSWw")

def ssh_remote(tokens):
    """ssh の遠隔コマンドの語を返す。宛先が無ければ None、遠隔コマンドが無ければ []。"""
    index = 1
    while index < len(tokens) and tokens[index].startswith("-") and tokens[index] != "-":
        option = tokens[index]
        index += 2 if option[-1] in SSH_TAKES_VALUE and len(option) == 2 else 1
    if index >= len(tokens):
        return None
    return tokens[index + 1:]

def _shell_options(tokens):
    """bash 系シェルの起動のオプションを読む: (-c があるか, -s があるか, 残りの語)。

    短いオプションの連結 (-lc) だけを旗として読み、--norc 等の長いオプションの中の文字は読まない。
    - と -- はオプションの終わりで、その次の語から残り。
    """
    index, run_string, read_stdin = 1, False, False
    while index < len(tokens):
        option = tokens[index]
        if option in {"-", "--"}:
            index += 1
            break
        if option.startswith("--"):
            index += 2 if option in {"--rcfile", "--init-file"} else 1
            continue
        if option[:1] in {"-", "+"} and len(option) > 1:
            run_string = run_string or "c" in option[1:]
            read_stdin = read_stdin or "s" in option[1:]
            index += 2 if option[-1] in "oO" else 1
            continue
        break
    return run_string, read_stdin, tokens[index:]

def shell_c_string(tokens):
    """bash 系シェルの -c の文字列 (無ければ None)。"""
    if executable(tokens[0]) not in SHELLS:
        return None
    run_string, _, rest = _shell_options(tokens)
    return rest[0] if run_string and rest else None

def reads_stdin_script(tokens):
    """標準入力の本文をそのままスクリプトとして実行する bash 系シェルの起動か (bash -s・bash /dev/stdin・
    引数なしの bash・source /dev/stdin)。"""
    name = executable(tokens[0])
    if name in {"source", "."}:
        return tokens[1:2] == ["/dev/stdin"]
    if name in SHELLS:
        run_string, read_stdin, rest = _shell_options(tokens)
        return not run_string and (read_stdin or not rest or rest[0] == "/dev/stdin")
    return False

def string_scripts(tokens):
    """文字列を別のシェルで実行する引数を (文字列, 方言, 説明) の列で返す。"""
    name = executable(tokens[0])
    scripts = []
    text = shell_c_string(tokens)
    if text is not None:
        scripts.append((text, "bash", f"{name} -c の引数"))
    source = powershell_script_source(tokens)
    if source is not None:
        scripts.append((source, "powershell", f"{name} -Command の引数"))
    if name == "eval" and len(tokens) > 1:
        scripts.append((" ".join(tokens[1:]), "bash", "eval の引数"))
    if name == "trap":
        arguments = tokens[2:] if tokens[1:2] == ["--"] else tokens[1:]
        if len(arguments) >= 2 and arguments[0] not in {"", "-"} and not arguments[0].startswith("-"):
            scripts.append((arguments[0], "bash", "trap の処理"))
    if name == "ssh":
        remote = ssh_remote(tokens)
        if remote:
            # ssh は遠隔コマンドの語を空白で連結して遠隔のシェルに渡す
            scripts.append((" ".join(remote), "bash", "ssh の遠隔コマンド"))
    if name in {"invoke-expression", "iex"}:
        text = invoke_expression_text(tokens)
        if text is not None:
            scripts.append((text, "powershell", "Invoke-Expression の引数"))
    if name == "cmd":
        for index, option in enumerate(tokens[1:], start=1):
            if option.lower() == "/c":
                # cmd の構文 (&&・||・|・& で区切る) は単純コマンドの範囲では bash と同じに読める (近似)
                scripts.append((" ".join(tokens[index + 1:]), "bash", "cmd /c の引数"))
                break
    return scripts


class Tree:
    """1 つのテキストを 1 つの方言で読んだ結果。"""

    def __init__(self, origin):
        self.origin = origin
        self.commands = []   # 前置きを剥がした語の列
        self.scripts = []    # (文字列, 方言, 説明): 別のシェルで実行する引数・シェルが読む本文
        self.outer = False   # --shell powershell で、外側のコマンドを bash として読んだ木か


# ---- bash: shfmt の構文木 ----

ANSI_C = re.compile(r"\\(x[0-9A-Fa-f]{1,2}|u[0-9A-Fa-f]{1,4}|U[0-9A-Fa-f]{1,8}|[0-7]{1,3}|c.|.)", re.S)

ANSI_C_SIMPLE = {"a": "\a", "b": "\b", "e": "\x1b", "E": "\x1b", "f": "\f", "n": "\n", "r": "\r",
                 "t": "\t", "v": "\v", "\\": "\\", "'": "'", '"': '"', "?": "?"}

def decode_ansi_c(text):
    def replace(match):
        code = match.group(1)
        try:
            if code[0] in "xuU" and len(code) > 1:
                return chr(int(code[1:], 16))
            if code[0] in "01234567":
                return chr(int(code, 8) & 0xFF)
        except (ValueError, OverflowError):
            return "\\" + code  # 範囲外の \U7fffffff 等は元の表記のまま残す
        if code[0] == "c" and len(code) == 2:
            return chr(ord(code[1]) & 0x1F)
        return ANSI_C_SIMPLE.get(code, "\\" + code)

    return ANSI_C.sub(replace, text)

def unescape_unquoted(text):
    return re.sub(r"\\(\n|.)", lambda m: "" if m.group(1) == "\n" else m.group(1), text, flags=re.S)

def unescape_double_quoted(text):
    return re.sub(r"\\([$`\"\\\n])", lambda m: "" if m.group(1) == "\n" else m.group(1), text)

def _offset(node, key):
    # shfmt の JSON は 0 の値を省くため、先頭 (Offset 0) の位置は Offset が無いことがある
    return (node.get(key) or {}).get("Offset", 0)


class BashTree:
    """shfmt の構文木から、起動されるコマンドと、別のシェルで実行する文字列・本文を集める。"""

    def __init__(self, source, tree):
        self.source = source.encode("utf-8")  # jq_text 済み (単独のサロゲートを含まない)
        self.tree = tree

    def text(self, node):
        return self.source[_offset(node, "Pos"):_offset(node, "End")].decode("utf-8")

    def word(self, word, in_double=False):
        """語を文字列にする。展開 (変数・置換) は値が分からないので元の表記のまま残す。"""
        out = []
        for part in word.get("Parts") or []:
            kind = part.get("Type")
            if kind == "Lit":
                value = part.get("Value", "")
                out.append(unescape_double_quoted(value) if in_double else unescape_unquoted(value))
            elif kind == "SglQuoted":
                value = part.get("Value", "")
                out.append(decode_ansi_c(value) if part.get("Dollar") else value)
            elif kind == "DblQuoted":
                out.append(self.word(part, in_double=True))
            else:
                out.append(self.text(part))
        return "".join(out)

    def walk(self, node, in_double=False):
        if isinstance(node, list):
            for item in node:
                self.walk(item, in_double)
            return
        if not isinstance(node, dict):
            return
        kind = node.get("Type")
        command = node.get("Cmd")
        if isinstance(command, dict) and command.get("Type") == "CallExpr":
            self.statement(node, command)
        if kind == "SglQuoted" and in_double and ("$(" in node.get("Value", "") or "`" in node.get("Value", "")):
            # "${x:-'$(cmd)'}" の ' は二重引用の中では引用にならず、$(cmd) は実行される。
            # shfmt はこれを単引用として木にするため、二重引用の中身として解析し直す。
            self.tree.scripts.append((': "' + node["Value"] + '"', "bash", "二重引用内のパラメータ展開"))
        if kind == "BinaryCmd" and node.get("Op") == "|":
            self.piped_body(node.get("X") or {}, node.get("Y") or {})
        if kind == "DblQuoted":
            in_double = True
        elif kind in {"CmdSubst", "ProcSubst"}:
            in_double = False
        for key, value in node.items():
            if key not in {"Pos", "End", "Comments"} and isinstance(value, (dict, list)):
                self.walk(value, in_double)

    def statement(self, stmt, call):
        tokens = unwrap([self.word(word) for word in call.get("Args") or []])
        if not tokens:
            return
        self.tree.commands.append(tokens)
        self.tree.scripts.extend(string_scripts(tokens))
        if reads_stdin_script(tokens):
            for redirect in stmt.get("Redirs") or []:
                body = self.redirect_body(redirect)
                if body is not None:
                    self.tree.scripts.append((body, "bash", f"{executable(tokens[0])} に流す本文"))

    def call_tokens(self, stmt):
        call = stmt.get("Cmd") or {}
        return unwrap([self.word(word) for word in call.get("Args") or []]) if call.get("Type") == "CallExpr" else []

    def piped_body(self, left, right):
        """`cat <<'EOF' | bash` の形: 引数なしの cat に流した本文を、右側のシェルがスクリプトとして読む。"""
        receiver = self.call_tokens(right)
        if self.call_tokens(left) != ["cat"] or not receiver or not reads_stdin_script(receiver):
            return
        for redirect in left.get("Redirs") or []:
            body = self.redirect_body(redirect)
            if body is not None:
                self.tree.scripts.append((body, "bash", f"cat から {executable(receiver[0])} に流す本文"))

    def redirect_body(self, redirect):
        if (redirect.get("N") or {}).get("Value", "0") != "0":
            return None  # 3<<<x のような別の fd への入力
        op = redirect.get("Op")
        if op in {"<<", "<<-"} and redirect.get("Hdoc"):
            delimiter = redirect.get("Word") or {}
            literal = any(part.get("Type") != "Lit" or "\\" in part.get("Value", "")
                          for part in delimiter.get("Parts") or [])
            parts = redirect["Hdoc"].get("Parts") or []
            # 引用した区切りなら本文はそのまま。未引用なら \$ などの退避を戻す (外側の展開は walk が拾う)。
            # <<- では本文の位置情報が終端行まで及ぶため、Lit は位置ではなく値から取る
            body = "".join(p.get("Value", "") if literal or p.get("Type") == "Lit" else self.text(p) for p in parts)
            return body if literal else unescape_double_quoted(body)
        return None


SURROGATE = re.compile("[\ud800-\udfff]")


def jq_text(text):
    """jq と同じく、単独のサロゲートを U+FFFD に置き換える。

    hook 入力の JSON は "\\ud800" のような単独のサロゲートを含み得る。そのままでは UTF-8 にできず
    (UnicodeEncodeError)、解析器にも渡せない。以前のガードは jq -r の出力 (U+FFFD に置き換え済み) を読んでいた。
    """
    return SURROGATE.sub("\ufffd", text)


def parse_bash(source, deadline):
    shfmt = parser_tools.resolve("shfmt")
    try:
        proc = subprocess.run([shfmt, "-ln", "bash", "--to-json"],
                              input=jq_text(source).encode("utf-8"),
                              capture_output=True, timeout=deadline.remaining())
    except subprocess.TimeoutExpired:
        raise parser_tools.ParserUnavailable("deadline", f"shfmt の解析が締切 ({deadline.limit:g} 秒) を超えた")
    except OSError as error:
        raise parser_tools.ParserUnavailable("shfmt", f"shfmt を起動できなかった ({error})")
    if proc.returncode != 0:
        message = proc.stderr.decode("utf-8", "replace").strip()
        if re.match(r"\d+:\d+: ", message):
            raise ScriptSyntaxError(" / ".join(message.splitlines()))
        raise parser_tools.ParserUnavailable("shfmt", f"shfmt が異常終了した (終了コード {proc.returncode}: {message})")
    return json.loads(proc.stdout)

def bash_tree(source, origin, deadline):
    tree = Tree(origin)
    source = jq_text(source)
    BashTree(source, tree).walk(parse_bash(source, deadline))
    return tree


# ---- PowerShell: 言語の Parser の構文木 ----

# PowerShell の構文木を作るスクリプト (-File で渡す。-EncodedCommand で渡すとコマンドラインが長くなり、
# scoop の shim を経由すると遅くなる・起動できないため)
PS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ps-commands.ps1")

def windows_split(text):
    """Windows の CommandLineToArgvW と同じ規則でコマンドラインを引数に分ける。"""
    arguments, current, in_quotes, has_argument, index = [], [], False, False, 0
    while index < len(text):
        char = text[index]
        if char == "\\":
            end = index
            while end < len(text) and text[end] == "\\":
                end += 1
            count = end - index
            if end < len(text) and text[end] == '"':
                # 2n 個の \ と " は n 個の \ と引用の切り替え、2n+1 個なら n 個の \ と文字の "
                current.append("\\" * (count // 2))
                if count % 2:
                    current.append('"')
                    end += 1
            else:
                current.append("\\" * count)
            index, has_argument = end, True
            continue
        if char == '"':
            if in_quotes and text[index + 1:index + 2] == '"':
                current.append('"')
                index += 2
                continue
            in_quotes, has_argument = not in_quotes, True
        elif char in " \t" and not in_quotes:
            if has_argument:
                arguments.append("".join(current))
                current, has_argument = [], False
        else:
            current.append(char)
            has_argument = True
        index += 1
    if has_argument:
        arguments.append("".join(current))
    return arguments


def powershell_parse(source, deadline):
    pwsh = parser_tools.resolve("pwsh")
    try:
        proc = subprocess.run([pwsh, "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                               "-File", PS_FILE],
                              input=jq_text(source).encode("utf-8"),
                              capture_output=True, timeout=deadline.remaining())
    except subprocess.TimeoutExpired:
        raise parser_tools.ParserUnavailable("deadline", f"PowerShell の解析が締切 ({deadline.limit:g} 秒) を超えた")
    except OSError as error:
        raise parser_tools.ParserUnavailable("pwsh", f"PowerShell を起動できなかった ({error})")
    try:
        result = json.loads(proc.stdout.decode("utf-8"))
    except ValueError:
        stderr = " ".join(proc.stderr.decode("utf-8", "replace").split())[:200]
        raise parser_tools.ParserUnavailable(
            "pwsh", f"PowerShell の解析結果を読めなかった (終了コード {proc.returncode}: {stderr})")
    if result.get("errors"):
        raise ScriptSyntaxError(" / ".join(result["errors"]))
    return result


def powershell_tree(source, origin, deadline):
    result = powershell_parse(source, deadline)
    tree = Tree(origin)
    for item in result.get("commands") or []:
        start = item.get("start")
        if start:
            # Start-Process は ArgumentList を空白で連結した 1 本のコマンドラインで起動し、
            # 起動先は Windows の規則 (CommandLineToArgvW) で引数に分ける
            words = [start["file"]] + windows_split(" ".join(start.get("arguments") or []))
        else:
            words = item.get("words") or []
        tokens = unwrap(words)
        if not tokens:
            continue
        tree.commands.append(tokens)
        tree.scripts.extend(string_scripts(tokens))
    return tree


# ---- 構文木の判定 ----

class Deadline:
    def __init__(self, limit):
        self.limit = limit
        self.start = time.monotonic()

    def remaining(self):
        left = self.limit - (time.monotonic() - self.start)
        if left <= 0:
            raise parser_tools.ParserUnavailable("deadline", f"解析が締切 ({self.limit:g} 秒) を超えた")
        return left


# hook の timeout (10 秒) より前に必ず結論を出す。超えたら以前の判定へ戻す。

DEADLINE_SECONDS = float(os.environ.get("AGENT_GUARD_DEADLINE_SECONDS", "6"))


class Analysis:
    def __init__(self, commands, origins, notice="", outer=None):
        self.commands = commands  # 語の列の列
        self.origins = origins    # 各コマンドを、どこで何として読んだか
        self.notice = notice      # 解析器が使えなかった等、ユーザーに知らせること
        self.outer = outer or [False] * len(commands)  # 各コマンドが、PS モードで外側を bash として読んだものか


class Analyzer:
    """テキストを木にし、別のシェルで実行する文字列とシェルが読む本文を同じ手順で読む。"""

    def __init__(self, shell, deadline):
        self.shell = shell
        self.deadline = deadline
        self.commands = []
        self.origins = []
        self.outer = []
        self.notices = []
        self.seen = set()

    def run(self, command):
        both = ["powershell", "bash"] if self.shell == "powershell" else ["bash"]
        pending = [(command, both, "コマンド")]
        for depth in range(MAX_DEPTH + 1):
            pending = [item for item in pending if (item[0], tuple(item[1])) not in self.seen]
            if not pending:
                return
            pending = pending[:max(0, MAX_SCRIPTS - len(self.seen))]  # 上限を超えた分は構文木では読まない
            for text, dialects, _ in pending:
                self.seen.add((text, tuple(dialects)))
            jobs = [(text, dialect, label, depth == 0) for text, dialects, label in pending for dialect in dialects]
            pending = []
            for trees in parallel(lambda job: self.read(*job), jobs):
                for tree in trees:
                    for tokens in tree.commands:
                        self.commands.append(tokens)
                        self.origins.append(tree.origin)
                        self.outer.append(tree.outer)
                    pending.extend((text, [dialect], label) for text, dialect, label in tree.scripts)

    def read(self, text, dialect, label, top):
        """text を dialect として読んだ木の列。構文エラーなら読まない (以前の判定が別に全体を読む)。"""
        origin = f"{'PowerShell' if dialect == 'powershell' else 'bash'} として読んだ{label}" \
            if self.shell == "powershell" else label
        try:
            tree = powershell_tree(text, origin, self.deadline) if dialect == "powershell" else \
                bash_tree(text, origin, self.deadline)
        except ScriptSyntaxError:
            return []
        except parser_tools.ParserUnavailable as error:
            self.notices.append(parser_tools.unavailable_notice(error, f"{label}は構文木では読まず、以前の判定だけで判定した"))
            return []
        tree.outer = self.shell == "powershell" and dialect == "bash" and top
        return [tree]


def parallel(function, items):
    items = list(items)
    if len(items) <= 1:
        return [function(item) for item in items]
    with ThreadPoolExecutor(min(PARALLEL, len(items))) as pool:
        return list(pool.map(function, items))


def analyze(command, shell, deadline=None):
    """command を構文木で読み、起動され得るコマンドの列を返す (以前の判定とは独立。止めるものを足すだけ)。"""
    analyzer = Analyzer(shell, deadline or Deadline(DEADLINE_SECONDS))
    try:
        analyzer.run(command)
    except Exception as error:  # noqa: BLE001 - hook を落とさないための受け皿。足すものが無いだけ
        analyzer.notices.append(f"構文木の判定の内部エラー ({type(error).__name__}: {error})")
    return Analysis(analyzer.commands, analyzer.origins, "。".join(dict.fromkeys(analyzer.notices)), analyzer.outer)


def setup_stdout():
    # Windows の Python は既定で cp932・CRLF で書き、日本語の理由文が化け、行末に CR が残る。
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")

def one_line(text):
    return " ".join(str(text).split())

def shell_argument(argv):
    """hook への引数 `--shell powershell` (Codex on Windows) を読む。無ければ bash。"""
    if "--shell" in argv and argv.index("--shell") + 1 < len(argv):
        return argv[argv.index("--shell") + 1]
    return "bash"

def tool_command(raw):
    """hook 入力の tool_input.command (または cmd)。argv の配列なら bash の 1 行にする。"""
    try:
        tool_input = json.loads(raw).get("tool_input") or {}
    except (ValueError, AttributeError):
        return ""
    if not isinstance(tool_input, dict):
        return ""
    command = tool_input.get("command") or tool_input.get("cmd")
    if isinstance(command, list) and all(isinstance(item, str) for item in command):
        return shlex.join(command)
    return command if isinstance(command, str) else ""


def explain(classify, analysis):
    """構文木の判定で止めたコマンドを、どこで何として読んだか。"""
    for tokens, origin, outer in zip(analysis.commands, analysis.origins, analysis.outer):
        if classify([tokens]):
            if outer:
                origin = f"PowerShell の構文木では見つからなかったが、外側を bash として読むと実行する ({origin})"
            return f"構文木の判定 ({origin}): `{' '.join(tokens)}`"
    return ""


HEAD_READINGS = {
    "reboot": "ヒアドキュメントの本文の行も含め、各行をコマンドとして読む近似の読み",
    "control-loss": "ヒアドキュメントの本文の行も含め、各行をコマンドとして読む近似の読み",
    "gh": "ヒアドキュメントの本文を除き、コマンドの位置にある gh から次の区切りまでの語をつないで"
          "正規表現を当てる近似の読み",
}


def head_judgement(head, command):
    """以前の判定 (head_judge) を command に当てる。gh は以前どおり hook 入力の JSON で渡す。"""
    if head == "reboot":
        return head_judge.reboot(command)
    if head == "control-loss":
        return head_judge.control_loss(command)
    return head_judge.gh(head_judge.hook_input_with(command))


def head_explanation(head, detail):
    where = f"以前の判定 ({HEAD_READINGS[head]})"
    if head == "reboot":
        # 以前の判定は入れ子が 4 段を超えたときも対象ありと同じ終了コードを返すため、どちらかは区別できない
        return f"{where}で止めた (入れ子が 4 段を超えた場合も含む)"
    if head == "control-loss" and detail == "unknown":
        return f"{where}、bash -c 等の入れ子が 4 段を超えたため止めた"
    return f"{where}で見つかった"


# ---- 以前の判定が分割できなかった理由 (判定は変えない。止めた理由を示すだけ) ----

def shlex_failure(text):
    """以前の判定と同じ shlex の規則 (posix・改行を " ; " にして 1 行で読む・引用の外の # から後ろはコメント) で
    text を読み、分割できない原因の (行番号, 文字) を返す。文字は閉じられない引用符か、後ろに文字が無い \\。
    分割できれば None。"""
    index, quote, opened = 0, None, 0
    while index < len(text):
        char = text[index]
        if quote is None:
            if char == "#":
                return None  # 改行も " ; " になっているので、残りはすべてコメント
            if char == "\\":
                if index + 1 == len(text):
                    return text.count("\n", 0, index) + 1, "\\"
                index += 2
                continue
            if char in "'\"":
                quote, opened = char, index
        elif quote == '"' and char == "\\":
            index += 2
            continue
        elif char == quote:
            quote = None
        index += 1
    if quote is None:
        return None
    return text.count("\n", 0, opened) + 1, quote


HEAD_SEPARATORS = {";", "|", "||", "&", "&&", "(", ")"}


def nested_shlex_failure(text, depth=0):
    """以前の再起動・操作不能の判定と同じく bash/sh/zsh の -c の文字列を入れ子で読み、最初に分割できない
    (文字列, (行番号, 文字))。外側が分割できなければ文字列は text。見つからなければ None。"""
    found = shlex_failure(text)
    if found:
        return text, found
    if depth >= 3:
        return None
    lexer = shlex.shlex(text.replace("\n", " ; "), posix=True, punctuation_chars="();|&")
    lexer.whitespace_split = True
    try:
        tokens = list(lexer)
    except ValueError:
        return None
    shell = False
    for index, token in enumerate(tokens[:-1]):
        if token in HEAD_SEPARATORS:
            shell = False
        elif executable(token) in SHELLS:
            shell = True
        elif shell and token.startswith("-") and "c" in token[1:]:
            result = nested_shlex_failure(tokens[index + 1], depth + 1)
            if result:
                return result
    return None


def heredoc_kept_lines(command):
    """以前の gh の判定 (strip_heredocs) が残す行の、元のコマンドでの行番号 (1 始まり) の列。
    strip_heredocs と同じ手順で数え、結果が strip_heredocs と一致しなければ None。"""
    legacy = head_judge.legacy_module()
    kept, pending = [], []
    lines = command.split("\n")
    for number, line in enumerate(lines, start=1):
        if pending:
            marker, allow_indent = pending[0]
            if (line.strip() if allow_indent else line.rstrip()) == marker:
                pending.pop(0)
            continue
        kept.append(number)
        pending.extend((match.group(3), bool(match.group(1))) for match in legacy["HEREDOC"].finditer(line))
    stripped = legacy["strip_heredocs"](command)
    return kept if "\n".join(lines[number - 1] for number in kept) == stripped else None


def head_split_where(head, command):
    """以前の判定が command を分割できなかった箇所 (「2 行目の ' を閉じられない」と原因の文字)。特定できなければ None。

    以前の判定が読んだのと同じテキストで数える。再起動・操作不能は jq の出力と同じく NUL と末尾の改行を除いたもの、
    gh・readback はヒアドキュメントの本文を除いたもの (行番号は元のコマンドの行に戻す)。"""
    if head == "gh":
        found = shlex_failure(head_judge.legacy_module()["strip_heredocs"](command))
        if not found:
            return None
        kept = heredoc_kept_lines(command)
        line = kept[found[0] - 1] if kept and found[0] <= len(kept) else None
        inside, char = "", found[1]
    else:
        text = jq_text(command).replace("\x00", "").rstrip("\n")
        result = nested_shlex_failure(text)
        if not result:
            return None
        nested, (line, char) = result
        inside = "" if nested == text else f"bash -c 等に渡した文字列 `{one_line(nested)[:60]}` の "
    at = f"{inside}{line} 行目の" if line else f"{inside}どこかの行の"
    if char == "\\":
        return f"{at}末尾の \\ の後に文字が無い", char
    return f"{at} {char} を閉じられない", char


HEAD_SPLIT_READINGS = {
    "reboot": "shlex による近似の読み。ヒアドキュメントの本文の行もコマンドとして読む",
    "control-loss": "shlex による近似の読み。ヒアドキュメントの本文の行もコマンドとして読む",
    "gh": "shlex による近似の読み。ヒアドキュメントの本文は読まない",
}


def head_split_failure(head, command, shell="bash"):
    """以前の判定が分割できずに止めたときの理由と避け方。"""
    reading = f"以前の判定 ({HEAD_SPLIT_READINGS[head]})"
    found = head_split_where(head, command)
    if not found:
        return f"{reading} がコマンドを分割できず (閉じられない引用符の位置は特定できなかった)、判定できずに止めた"
    where, char = found
    if char == "\\":
        hint = "末尾の \\ を消すこと"
    else:
        # どのガードも通る書き方を案内する。以前の判定は、本文に " が無い二重引用を 1 語として読む
        example = ("本文に \" と $ とバッククォートが無ければ -m @\"…\"@" if shell == "powershell"
                   else "本文に \" が無ければ -m \"$(cat <<'EOF' … EOF)\" や --body \"$(cat <<'EOF' … EOF)\"")
        hint = (f"本文の引用符が対になる書き方 (例: {example}) にするか、引用符を使わない書き方にすること。"
                "git の本文はファイル編集のツールで書いたファイルを -F で渡してもよい。"
                "ファイルを書くだけならシェルではなくファイル編集のツールを使う")
    return f"{reading} が {where}ため、判定できずに止めた。{hint}"


def parser_notice():
    """構文解析器 (shfmt) が使えないときの導入状況の通知文。使えれば空。"""
    try:
        parser_tools.resolve("shfmt")
    except parser_tools.ParserUnavailable as error:
        return parser_tools.unavailable_notice(error, "構文木は読めない")
    return ""


def judge(head, classify, raw, shell, deadline):
    """(status, detail, notice, explanation)。合成の手順は冒頭の docstring を参照。"""
    head_command = head_judge.hook_command(raw) if head != "gh" else tool_command(raw)
    status, detail = head_judge.gh(raw) if head == "gh" else head_judgement(head, head_command)
    if status == "match":
        return "match", detail, parser_notice(), head_explanation(head, detail)
    if status == "undecidable":
        return "undecidable", head_split_failure(head, head_command, shell), parser_notice(), ""
    command = tool_command(raw)
    analysis = analyze(command, shell, deadline) if command else Analysis([], [])
    result = classify(analysis.commands)
    if result:
        return "match", result, analysis.notice, explain(classify, analysis)
    return "none", "", analysis.notice, ""


def guard_main(classify, argv, head):
    """PreToolUse ガードの共通入口。5 行で結果を返す。

    1 行目: none / match / undecidable
    2 行目: match なら結果 (以前の判定なら以前と同じ表記)、undecidable なら理由
    3 行目: 解析器の通知文 (無ければ空)
    4 行目: 通知文を今回ユーザーへ出すか (1/0。同じ通知を毎回出さないため)
    5 行目: match のとき、どの判定のどこで見つけたか
    """
    setup_stdout()
    raw = sys.stdin.buffer.read()
    status, detail, notice, explanation = judge(head, classify, raw, shell_argument(argv), Deadline(DEADLINE_SECONDS))
    # 止めるときは理由に必ず通知文を入れるので、間引きの印は通すときだけ使う
    notify = parser_tools.should_notify(notice) if notice and status == "none" else False
    print(status)
    print(one_line(detail))
    print(one_line(notice))
    print("1" if notify else "0")
    print(one_line(explanation))
