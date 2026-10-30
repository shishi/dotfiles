"""Report how personal memories were offered and retrieved in Claude Code / Codex transcripts.

usage: memory-usage-report.py [--since YYYY-MM-DD] [--json] <memory-repo> <commit>
The counts are evidence for consolidation reviews, not a deletion criterion.
A retrieval is a successful `git -C <memory repo> show`, a body delivered by a hook lookup, or a
Read of a memory file, made after the hook output of the same user input.
"""

import argparse
import glob
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys

# Only the hook's own first line counts: instructions and pasted text may quote the marker.
HOOK_OUTPUT = re.compile(r"(?m)^\[記憶検索\] 確定済み記憶の語句検索")
CANDIDATES = re.compile(r"語句検索の候補[^:：\n]*[:：]\s*([^\n]+)")
MEMORY_REPO = re.compile(r"agent-memory|\.(?:claude|codex)/memory")
REVISION_PATH = re.compile(r"[\w./^{}@-]+:([\w./-]+\.md)")
MEMORY_PATH = re.compile(r"(?:agent-memory|\.(?:claude|codex)/memory)/([\w./-]+\.md)")
# The lookup prints JSON, which stays escaped when a shell warning precedes it in the tool output.
DELIVERED = re.compile(r'<retrieved-memory path=\\*"([^"\\]+)')
# Codex runs shell commands from exec scripts as tools.exec_command({cmd: <string literal>}).
# The literal must be the whole property value; concatenations and other expressions are not read.
EXEC_CALL = re.compile(r"exec_command\s*\(")
EXEC_COMMAND = re.compile(r"""exec_command\s*\(\s*\{[^{}]*?\bcmd\s*:\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'|`((?:[^`\\]|\\.)*)`)(?=\s*[,}])""", re.S)
JS_ESCAPES = {"n": "\n", "r": "\r", "t": "\t", "b": "\b", "f": "\f", "v": "\v", "\n": ""}
TRUNCATION = re.compile(r"Warning: truncated output[^\n]*\n(?:Total output lines: \d+\n)?")
SHELL_OPERATORS = ("&&", "||", ";", "|", "&", "\n")
LIST_SEPARATORS = ("", ";", "&", "\n")
SHELL_SYNTAX = ";&|'\" \t#`$()<>"
GIT_VALUE_OPTIONS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"}
# Bash and PowerShell words that open or continue a compound command.
COMPOUND_WORDS = {"if", "then", "elif", "else", "fi", "for", "while", "until", "do", "done", "case", "esac",
                  "select", "function", "!", "[[", "foreach", "switch", "try", "catch", "finally", "}"}
SHELL_TOOLS = {"Bash", "PowerShell", "shell", "shell_command", "exec_command", "local_shell"}


def git(repo, *args):
    return subprocess.check_output(["git", "-C", repo, *args]).decode("utf-8")


def strings_of(value):
    """Collect the text of a tool input or result without JSON escaping."""
    if isinstance(value, str):
        try:
            decoded = json.loads(value)
        except ValueError:
            return value
        return strings_of(decoded) if isinstance(decoded, (dict, list)) else value
    if isinstance(value, dict):
        return "\n".join(strings_of(item) for item in value.values())
    if isinstance(value, list):
        return "\n".join(strings_of(item) for item in value)
    return ""


def json_values(text):
    """The JSON values that make up the whole text; ValueError when anything else is in it."""
    decoder, values, index = json.JSONDecoder(), [], 0
    text = text.strip()
    while index < len(text):
        value, index = decoder.raw_decode(text, index)
        values.append(value)
        while index < len(text) and text[index].isspace():
            index += 1
    return values


def wrapper_codes(value):
    """Exit codes of the command results inside a decoded tool wrapper."""
    if isinstance(value, list):
        return [code for item in value for code in wrapper_codes(item)]
    if not isinstance(value, dict):
        return []
    if "chunk_id" in value:
        return [value.get("exit_code")]
    if isinstance(value.get("metadata"), dict):
        return [value["metadata"].get("exit_code")]
    return [code for item in value.values() for code in wrapper_codes(item)]


def exit_status(output):
    """True/False from the exit codes the tool wrapper reports, None when it reports none.

    Only the wrapper is read: a leading exit notice, or output items that consist of the JSON an
    exec script or function call returns. Text printed by the command itself is not.
    """
    texts = [output] if isinstance(output, str) else [
        item.get("text", "") if isinstance(item, dict) else item for item in output or [] if isinstance(item, (dict, str))]
    codes = []
    for text in texts:
        notice = re.match(r"\s*Process exited with code (-?\d+)", text)
        if notice:
            codes.append(int(notice[1]))
            continue
        body = text.lstrip()
        if truncated := TRUNCATION.match(body):
            body = body[truncated.end():]
        if not body.lstrip().startswith(("{", "[")):
            continue
        try:
            codes += wrapper_codes(json_values(body))
        except ValueError:
            # A truncated wrapper may have hidden a failure.
            codes.append(None)
    if not codes or None in codes:
        return None
    return all(code == 0 for code in codes)


def simple_commands(command):
    """The simple commands of a shell line as (preceding operator, words); None if unsupported.

    Command substitution, here-documents and escaped shell syntax are not modelled. Other
    backslashes are kept, since PowerShell and Windows paths use them as separators.
    """
    commands, words, word, operator, quote = [], [], None, "", None
    text, index = command.replace("\\\n", ""), 0
    while index < len(text):
        char, following = text[index], text[index + 1:index + 2]
        if quote:
            if char == quote:
                quote = None
            elif quote == '"' and (char == "`" or text.startswith("$(", index)):
                return None
            elif quote == '"' and char == "\\" and following in ('"', "\\"):
                word += following
                index += 1
            else:
                word += char
        elif char in "'\"":
            quote, word = char, word or ""
        elif char == "`" or text.startswith(("$(", "<<"), index):
            return None
        elif char == "\\" and following and following in SHELL_SYNTAX:
            # Bash reads this as an escaped character and PowerShell as a path separator.
            return None
        elif char == "#" and word is None:
            # A comment runs to the end of the line; the newline still separates commands.
            end = text.find("\n", index)
            index = len(text) if end < 0 else end
            continue
        elif char in " \t\r":
            if word is not None:
                words.append(word)
                word = None
        elif char == "&" and ((word or "").endswith((">", "<")) or following == ">"):
            word = (word or "") + char
        elif op := next((op for op in SHELL_OPERATORS if text.startswith(op, index)), None):
            if word is not None:
                words.append(word)
                word = None
            commands.append((operator, words))
            words, operator = [], op
            index += len(op)
            if op in ("&&", "||", "|"):
                # The command after a pipe or a conditional may follow blank and comment lines.
                while index < len(text) and (text[index] in " \t\r\n" or text[index] == "#"):
                    if text[index] == "#":
                        end = text.find("\n", index)
                        index = len(text) if end < 0 else end
                    else:
                        index += 1
            continue
        else:
            word = (word or "") + char
        index += 1
    if quote:
        return None
    # Blank lines, comments and a trailing separator leave commands without words.
    return [(op, found) for op, found in commands + [(operator, words + ([word] if word is not None else []))]
            if found]


def mentions_memory(text):
    return bool(MEMORY_REPO.search(text.replace("\\", "/"))) or "inject-memory.sh" in text


def command_reads(command):
    """Memory files read by `git -C <memory repo> show`, and whether the command runs a hook lookup.

    None when a command that names the memory repo or the lookup cannot be read: it uses an
    unsupported construct, reads the memory repo in a form not parsed here, or reads where the
    call's exit code does not show that the read ran. A read that ran unconditionally but whose
    own failure a later command hides is still counted.
    """
    if not mentions_memory(command):
        return set(), False
    commands = simple_commands(command)
    # Compound commands (if, loops, groups, subshells) decide at run time which reads run.
    if commands is None or any(words[0] in COMPOUND_WORDS or words[0].startswith(("(", "{")) for _, words in commands):
        return None
    if not commands:
        return set(), False
    # The call's exit code comes from the last list; lists end at ;, & and newlines.
    last_list = max(position for position, (operator, _) in enumerate(commands) if operator in LIST_SEPARATORS)
    paths, lookup, guards = set(), False, set()
    for position, (operator, words) in enumerate(commands):
        guards = set() if operator in LIST_SEPARATORS else guards | ({operator} & {"&&", "||"})
        words = [word.replace("\\", "/") for word in words]
        reads, runs_lookup, parsed = set(), False, False
        if words[:1] == ["git"]:
            repo, index = "", 1
            while index < len(words) and words[index].startswith("-"):
                if words[index] in GIT_VALUE_OPTIONS and index + 1 < len(words):
                    repo = words[index + 1] if words[index] == "-C" else repo
                    index += 1
                index += 1
            if words[index:index + 1] == ["show"] and not repo:
                # The memory repo may be the working directory set by an earlier command.
                return None
            if words[index:index + 1] == ["show"] and MEMORY_REPO.search(repo):
                if any("$" in word for word in words[index + 1:]):
                    return None
                reads = {match[1] for word in words[index + 1:] if (match := REVISION_PATH.fullmatch(word))}
                parsed = True
        for index, word in enumerate(words[:-2]):
            if word.endswith("inject-memory.sh") and words[index + 2] == "lookup":
                runs_lookup = parsed = True
        if not parsed and "show" in words and any(MEMORY_REPO.search(word) for word in words):
            return None
        if (reads or runs_lookup) and ("||" in guards or (guards and position < last_list)):
            return None
        paths |= reads
        lookup = lookup or runs_lookup
    return paths, lookup


def file_reads(file_path):
    return set(MEMORY_PATH.findall((file_path or "").replace("\\", "/")))


def hook_output(text):
    match = HOOK_OUTPUT.search(text)
    return text[match.start():] if match else None


def claude_events(record):
    if record.get("isMeta"):
        return
    attachment = record.get("attachment") or {}
    if attachment.get("type") == "hook_additional_context" and attachment.get("hookEvent") == "UserPromptSubmit":
        context = hook_output(strings_of(attachment.get("content")))
        if context:
            yield "prompt", context
    # Inputs are delimited by the hook output above. A user record with turnOrigin also ends the
    # previous input, but queued prompts and peer messages may lack it; an input that gets no hook
    # output then leaves its reads with the previous input. Queued notifications arrive mid-turn
    # as well, so they do not end the input.
    if record.get("type") == "user" and record.get("turnOrigin"):
        yield ("input",)
    content = (record.get("message") or {}).get("content")
    if not isinstance(content, list):
        return
    for item in content:
        if not isinstance(item, dict):
            continue
        tool_input = item.get("input") or {}
        if item.get("type") == "tool_use" and item.get("name") in SHELL_TOOLS:
            reads = command_reads(strings_of(tool_input.get("command")))
            if reads is None:
                yield ("unparsed",)
            yield "attempt", item.get("id"), *(reads or (set(), False))
        elif item.get("type") == "tool_use" and item.get("name") == "Read":
            yield "attempt", item.get("id"), file_reads(tool_input.get("file_path")), False
        elif item.get("type") == "tool_result":
            text = strings_of(item.get("content"))
            yield "result", item.get("tool_use_id"), not item.get("is_error"), set(DELIVERED.findall(text))


def js_string(body):
    """The value of a JavaScript string literal's body; None for escapes this reader does not decode."""
    if re.search(r"\\[0-9xu]", body):
        return None
    return re.sub(r"\\(.)", lambda match: JS_ESCAPES.get(match[1], match[1]), body, flags=re.S)


def codex_commands(payload):
    """Shell commands of a Codex tool call; None for memory commands that cannot be read statically."""
    kind, name = payload.get("type"), payload.get("name")
    if kind == "custom_tool_call" and name == "exec":
        script = payload.get("input") or ""
        starts = [match.start() for match in EXEC_CALL.finditer(script)]
        commands = []
        for start, end in zip(starts, starts[1:] + [len(script)]):
            literal = EXEC_COMMAND.match(script, start)
            if literal:
                template = literal[3]
                body = next((group for group in literal.groups() if group is not None), "")
                command = None if template and "${" in template else js_string(body)
            else:
                # A cmd that is a variable or another expression cannot be read statically.
                command = None
            if command is not None or mentions_memory(script[start:end]):
                commands.append(command)
        return commands
    if kind == "function_call" and name in SHELL_TOOLS:
        try:
            arguments = json.loads(payload.get("arguments") or "{}")
        except ValueError:
            return [None]
        return [strings_of(arguments.get("cmd") or arguments.get("command"))]
    if kind == "local_shell_call":
        return [strings_of((payload.get("action") or {}).get("command"))]
    return []


def codex_events(record):
    payload = record.get("payload") or {}
    if record.get("type") == "event_msg" and payload.get("type") == "task_started":
        yield ("input",)
    if record.get("type") != "response_item":
        return
    kind = payload.get("type", "")
    if kind == "message" and payload.get("role") == "user":
        yield ("input",)
    elif kind == "message" and payload.get("role") == "developer":
        context = hook_output(strings_of(payload.get("content")))
        if context:
            yield "prompt", context
    elif kind.endswith("_output"):
        output = payload.get("output")
        # One exec script may run several commands, and one PowerShell line may chain several:
        # any non-zero code discards the whole call's reads, which can drop a successful read.
        yield "result", payload.get("call_id"), exit_status(output), set(DELIVERED.findall(strings_of(output)))
    elif kind.endswith("call"):
        paths, lookup = set(), False
        for command in codex_commands(payload):
            reads = None if command is None else command_reads(command)
            if reads is None:
                yield ("unparsed",)
                continue
            command_paths, command_lookup = reads
            paths |= command_paths
            lookup = lookup or command_lookup
        yield "attempt", payload.get("call_id"), paths, lookup


def transcripts(directories):
    for directory in directories:
        yield from glob.glob(os.path.join(directory, "**", "*.jsonl"), recursive=True)


def build_report(repo, commit, claude_dirs, codex_dirs, since):
    tree = [path for path in git(repo, "ls-tree", "-r", "--name-only", commit).splitlines() if path.endswith(".md")]
    files = {path: {"chars": len(git(repo, "show", f"{commit}:{path}")), "retrieved": 0, "candidate": 0, "outside": 0}
             for path in tree if path not in ("MEMORY.md", "CONVENTIONS.md")}
    prompts = []
    unknown_results = unparsed_commands = 0
    for parse, directories in ((claude_events, claude_dirs), (codex_events, codex_dirs)):
        for transcript in transcripts(directories):
            current = None
            pending = {}
            with open(transcript, encoding="utf-8", errors="replace") as handle:
                for line in handle:
                    try:
                        record = json.loads(line)
                    except ValueError:
                        continue
                    if record.get("timestamp", since) < since:
                        continue
                    for event in parse(record):
                        if event[0] == "input":
                            current, pending = None, {}
                        elif event[0] == "prompt":
                            listed = CANDIDATES.search(event[1])
                            names = {name.strip() for name in listed[1].split(",")} if listed else set()
                            current = {"chars": len(event[1]), "candidates": names & files.keys(), "retrieved": set()}
                            prompts.append(current)
                            pending = {}
                        elif current is None:
                            continue
                        elif event[0] == "unparsed":
                            unparsed_commands += 1
                        elif event[0] == "attempt":
                            pending[event[1]] = (event[2], event[3])
                        else:
                            _, call, succeeded, delivered = event
                            reads, lookup = pending.pop(call, (set(), False))
                            # A lookup counts only the bodies it delivered, not the path it was asked for.
                            found = (reads | (delivered if lookup else set())) & files.keys()
                            if succeeded:
                                current["retrieved"] |= found
                            elif succeeded is None and (reads or lookup):
                                unknown_results += 1
    for prompt in prompts:
        for path in prompt["candidates"]:
            files[path]["candidate"] += 1
        for path in prompt["retrieved"]:
            files[path]["retrieved"] += 1
            if path not in prompt["candidates"]:
                files[path]["outside"] += 1
    sizes = [prompt["chars"] for prompt in prompts]
    return {
        "since": since,
        "commit": commit,
        "index_chars": len(git(repo, "show", f"{commit}:MEMORY.md")),
        "prompts": len(prompts),
        "unknown_results": unknown_results,
        "unparsed_commands": unparsed_commands,
        "prompts_with_retrieval": sum(bool(prompt["retrieved"]) for prompt in prompts),
        "retrieved_in_candidates": sum(len(prompt["retrieved"] & prompt["candidates"]) for prompt in prompts),
        "retrieved_total": sum(len(prompt["retrieved"]) for prompt in prompts),
        "candidates_total": sum(len(prompt["candidates"]) for prompt in prompts),
        "prompt_context_chars_median": statistics.median(sizes) if sizes else 0,
        "prompt_context_chars_total": sum(sizes),
        "files": files,
    }


def print_text(report):
    print(f"期間: {report['since']} 以降 / 基準 commit: {report['commit']}")
    print(f"索引 MEMORY.md: {report['index_chars']} 文字（毎入力の注入に含まれる。Codex では起動時にも入る）")
    print(f"記憶検索 hook が動いた入力: {report['prompts']} 件、うち本文取得あり {report['prompts_with_retrieval']} 件")
    print(f"毎入力の記憶注入: 中央値 {report['prompt_context_chars_median']} 文字、合計 {report['prompt_context_chars_total']} 文字")
    print(f"取得した本文のうち候補一覧にあったもの: {report['retrieved_in_candidates']} / {report['retrieved_total']}"
          f"（候補一覧の延べ件数 {report['candidates_total']}）")
    print("CORE.md と現プロジェクトの記憶は起動時に自動注入されるため、取得回数に現れない。")
    print("取得は、hook が動いた入力の中で成功した `git -C <記憶 repo> show`・Read と、lookup が渡した本文だけを数える。"
          "サブエージェントの取得は含まない。")
    print(f"成否を判定できず数えなかった記憶の読み取り: {report['unknown_results']} 件、"
          f"記憶 repo か lookup を含むが解析できなかったコマンド: {report['unparsed_commands']} 件")
    print("「候補外」は、その入力の候補一覧に無かったのに取得された回数。索引の手がかりを直す対象になる。")
    print("文字数\t取得\t候補外\t候補\tパス")
    for path, row in sorted(report["files"].items(), key=lambda item: (-item[1]["retrieved"], -item[1]["chars"])):
        print(f"{row['chars']}\t{row['retrieved']}\t{row['outside']}\t{row['candidate']}\t{path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("repo")
    parser.add_argument("commit")
    parser.add_argument("--since", default="2026-01-01")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    home = Path.home()
    report = build_report(args.repo, args.commit, [str(home / ".claude/projects")], [str(home / ".codex/sessions")], args.since)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=1, default=sorted))
    else:
        print_text(report)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
