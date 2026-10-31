"""PowerShell の解析器が使えないときの構文木の判定を確かめる (parser-fallback.test.sh から呼ぶ)。

PowerShell が無い環境は作れないため、解析器の所在解決を差し替える。PowerShell は自動導入せず、
その本文は構文木では読まず (足すものが無いだけ。以前の判定は別に全体を読む)、外側の木は保つことを見る。
"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ["XDG_STATE_HOME"] = tempfile.mkdtemp()

import parser_tools  # noqa: E402
import shell_commands  # noqa: E402

real_resolve = parser_tools.resolve
started = []


def resolve(tool):
    if tool == "pwsh":
        raise parser_tools.ParserUnavailable("pwsh", "構文解析器の PowerShell が見つからない", missing=True)
    return real_resolve(tool)


real_ensure = parser_tools.ensure_install
parser_tools.resolve = resolve
parser_tools.ensure_install = lambda tool="shfmt": started.append(tool) or real_ensure(tool)

failures = 0


def check(label, ok, detail=""):
    global failures
    if not ok:
        failures += 1
        print(f"NG: {label} {detail}")


analysis = shell_commands.analyze("git status && pwsh -c 'shutdown /r'", "bash")
check("外側の bash の木は保つ", ["git", "status"] in analysis.commands, analysis.commands)
check("入れ子が解析できなかったことを知らせる", "PowerShell" in analysis.notice and "自動導入しない" in analysis.notice,
      analysis.notice)

# --shell powershell で PowerShell の解析器が無いときも導入しない。bash 側は読む
analysis = shell_commands.analyze("Restart-Computer -Force", "powershell")
check("bash として読んだ側は保つ", ["Restart-Computer", "-Force"] in analysis.commands, analysis.commands)
check("pwsh は導入しない", "pwsh" not in started, started)
sys.exit(1 if failures else 0)
