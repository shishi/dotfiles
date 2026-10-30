"""Report how personal memories were offered and retrieved in Claude Code / Codex transcripts.

usage: memory-usage-report.py [--since YYYY-MM-DD] [--json] <memory-repo> <commit>
The counts are evidence for consolidation reviews, not a deletion criterion.
A retrieval is a `git -C <memory repo> show` that the call's exit code shows ran (a failure hidden
by a later command still counts), a body delivered by a hook lookup, or a Read of a memory file,
made after the hook output of the same user input. Memory commands whose execution cannot be
established are listed as unparsed, so the counts are a lower bound.
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

# Codex compresses older session files (*.jsonl.zst); Python 3.14 and later can read them.
try:
    from compression import zstd
except ImportError:
    zstd = None

# Only the hook's own first line counts: instructions and pasted text may quote the marker.
HOOK_OUTPUT = re.compile(r"(?m)^\[記憶検索\] 確定済み記憶の語句検索")
CANDIDATES = re.compile(r"語句検索の候補[^:：\n]*[:：]\s*([^\n]+)")
# The memory link may also be named relative to the dotfiles checkout (codex/memory).
MEMORY_REPO = re.compile(r"agent-memory|\.?(?:claude|codex)/memory")
REVISION_PATH = re.compile(r"[\w./^{}@-]+:([\w./-]+\.md)")
MEMORY_PATH = re.compile(r"(?:agent-memory|\.?(?:claude|codex)/memory)/([\w./-]+\.md)")
WORKDIR = re.compile(r"""\bworkdir\b\s*(?::\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'|`((?:[^`\\$]|\\.)*)`)(?=\s*[,}]))?""")
# The lookup prints JSON, which stays escaped when a shell warning precedes it in the tool output.
DELIVERED = re.compile(r'<retrieved-memory path=\\*"([^"\\]+)')
# Codex runs shell commands from exec scripts as tools.exec_command({cmd: <string literal>}).
# The literal must be the whole property value; concatenations and other expressions are not read.
EXEC_CALL = re.compile(r"exec_command\s*\(")
EXEC_COMMAND = re.compile(r"""exec_command\s*\(\s*\{[^{}]*?\bcmd\s*:\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'|`((?:[^`\\]|\\.)*)`)(?=\s*[,}])""", re.S)
JS_ESCAPES = {"n": "\n", "r": "\r", "t": "\t", "b": "\b", "f": "\f", "v": "\v", "\n": ""}
TRUNCATION = re.compile(r"Warning: truncated output[^\n]*\n(?:Total output lines: \d+\n)?")
SHELL_OPERATORS = ("&&", "||", ";", "|", "&", "\n")
SHELL_SYNTAX = ";&|'\" \t#`$()<>"
GIT_VALUE_OPTIONS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"}
DIRECTORY_CHANGES = {"cd", "pushd", "set-location", "sl", "chdir"}
# Words that end the shell or the script, so later commands may not run.
TERMINATING = {"exit", "return", "exec", "logout", "break", "continue", "throw", "stop-process"}
# Bash and PowerShell words that open or continue a compound command (PowerShell ignores case
# and may attach the condition, as in `if($x)`).
COMPOUND = re.compile(r"(?:if|then|elif|else|fi|for|while|until|do|done|case|esac|select|function|foreach|switch"
                      r"|try|catch|finally|trap)(?![\w-])|[!{}(]|\[\[", re.I)
# In an exec script, a call surely runs when a top-level statement awaits it directly or inside
# the array of Promise.all / Promise.allSettled, and no earlier statement opens a condition, a loop
# or an unfinished expression that would govern it.
JS_STRINGS = re.compile(r"""//[^\n]*|/\*.*?\*/|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`""", re.S)
AWAITED_CALL = re.compile(r"\s*(?:(?:const|let|var)\s+[\w$]+\s*=\s*)?(?:text\(\s*)?(?:JSON\.stringify\(\s*)?"
                          r"await\s+(?:tools\.exec_command\(|Promise\.(?:all|allSettled)\(\s*\[)")
DIRECT_CALL = re.compile(r"\s*tools\.exec_command\(")
JS_CONTROL = re.compile(r"\s*(?:(?:if|else|for|while|do|switch|try|catch|finally|return|throw|with)\b|[\w$]+\s*:(?!:)"
                        r"|exit\s*\()")
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
    if value.get("status") == "rejected":
        # A settled rejection carries no exit code, so the call's result is unknown.
        return [None]
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
    # An exec script that failed or is still running does not show which of its calls ran.
    if texts and texts[0].startswith("Script ") and not texts[0].startswith("Script completed"):
        return None
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
    # Mixed codes from several commands do not show whether the read among them succeeded.
    if not codes or None in codes or (0 in codes and any(code != 0 for code in codes)):
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
        elif char == "&" and word is None and not words and following != "&":
            # PowerShell's call operator at the start of a command, not a separator.
            pass
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
    # Blank lines, comments and a trailing separator leave commands without words; an empty
    # command after & is kept, since the line's exit code then belongs to no list.
    return [(op, found) for op, found in commands + [(operator, words + ([word] if word is not None else []))]
            if found or op == "&"]


def mentions_memory(text):
    # Escaped backslashes in script source (C:\\Users\\...) are path separators too.
    return bool(MEMORY_REPO.search(re.sub(r"[\\/]+", "/", text))) or "inject-memory.sh" in text


def memory_read(words):
    """Paths read by `git ... -C <memory repo> ... show`, or True for a hook lookup; None otherwise."""
    words = [word.replace("\\", "/") for word in words]
    if words[:1] == ["git"]:
        repo, index = "", 1
        while index < len(words) and words[index].startswith("-"):
            if words[index] in GIT_VALUE_OPTIONS and index + 1 < len(words):
                repo = words[index + 1] if words[index] == "-C" else repo
                index += 1
            index += 1
        arguments = [word for word in words[index + 1:] if not word.startswith("-")]
        matches = [REVISION_PATH.fullmatch(word) for word in arguments]
        # Every argument must name a file at a revision in the repository's own path form.
        if (words[index:index + 1] == ["show"] and MEMORY_REPO.search(repo) and "$" not in "".join(words)
                and arguments and all(match and not match[1].startswith(".") for match in matches)):
            return {match[1] for match in matches}
        return None
    script = 1 if words[:1] in (["bash"], ["sh"]) else 0
    if words[script:script + 1] and words[script].endswith("inject-memory.sh") and words[script + 2:script + 3] == ["lookup"]:
        return True
    return None


def command_reads(command, in_memory=False):
    """Memory files read by `git -C <memory repo> show`, and whether the command runs a hook lookup.

    A read counts when the call's exit code shows that the shell reached it: the line uses only
    ;, newlines, && and pipes, no command ends the shell or opens a compound command, and a read
    after && is in the last list, whose exit code the call reports. A failure that a later command
    hides still counts. Any other line that names the memory repo or the lookup, or any line run
    in the memory repo (`in_memory`, the session's working directory), is None (unparsed): its
    read may not have run, or it reads memory in a form not parsed here.
    """
    if not mentions_memory(command) and not in_memory:
        return set(), False, True
    commands = simple_commands(command)
    if commands is None:
        return None
    if any(operator in ("||", "&") for operator, _ in commands[1:]):
        return None
    if any(words and (COMPOUND.match(words[0]) or words[0].lower() in TERMINATING) for _, words in commands):
        return None
    last_list = max((position for position, (operator, _) in enumerate(commands)
                     if position == 0 or operator in (";", "\n")), default=0)
    paths, lookup, guarded, reading = set(), False, False, []
    for position, (operator, words) in enumerate(commands):
        guarded = operator == "&&" or (guarded and operator == "|")
        read = memory_read(words)
        if read is None:
            first = words[0].lower() if words else ""
            # A directory change into memory makes later relative reads possible.
            if first in DIRECTORY_CHANGES and not in_memory:
                in_memory = mentions_memory(" ".join(words))
                continue
            # A git command whose repository comes from a variable may target memory. Without -C
            # it runs in the working directory, which `in_memory` covers.
            repo = words[words.index("-C") + 1] if "-C" in words[:-1] else ""
            if in_memory or (first == "git" and "$" in repo) or any(mentions_memory(word) for word in words):
                return None
            continue
        if guarded and position < last_list:
            return None
        if read is True:
            lookup = True
        else:
            paths |= read
        reading.append(position)
    # Only a single read at the end of the line owns the exit code; a failure code from another
    # command does not show that the read failed.
    return paths, lookup, reading in ([], [len(commands) - 1])


def file_reads(file_path):
    return set(MEMORY_PATH.findall((file_path or "").replace("\\", "/")))


def hook_output(text):
    match = HOOK_OUTPUT.search(text)
    return text[match.start():] if match else None


def claude_events(record, state):
    if record.get("isMeta"):
        return
    in_memory = mentions_memory(record.get("cwd") or "")
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
            reads = command_reads(strings_of(tool_input.get("command")), in_memory)
            # A background command returns before it finishes, without an exit code.
            if reads and (reads[0] or reads[1]) and tool_input.get("run_in_background"):
                reads = None
            if reads is None:
                yield ("unparsed",)
            yield "attempt", item.get("id"), *(reads or (set(), False, True))
        elif item.get("type") == "tool_use" and item.get("name") == "Read":
            yield "attempt", item.get("id"), file_reads(tool_input.get("file_path")), False, True
        elif item.get("type") == "tool_result":
            text = strings_of(item.get("content"))
            yield "result", item.get("tool_use_id"), not item.get("is_error"), set(DELIVERED.findall(text))


def js_string(body):
    """The value of a JavaScript string literal's body; None for escapes this reader does not decode."""
    if re.search(r"\\[0-9xu]", body):
        return None
    return re.sub(r"\\(.)", lambda match: JS_ESCAPES.get(match[1], match[1]), body, flags=re.S)


def closing(code, opening):
    """Index of the bracket that closes the one at `opening`, or None."""
    level = 0
    for index in range(opening, len(code)):
        level += (code[index] in "([{") - (code[index] in ")]}")
        if level == 0:
            return index
    return None


def awaited_calls(script):
    """Positions of the exec calls that surely run, mapped to the text of their call."""
    code = JS_STRINGS.sub(lambda literal: " " * len(literal[0]), script)
    statements, depth, start = [], 0, 0
    for index, char in enumerate(code):
        depth += (char in "([{") - (char in ")]}")
        if depth < 0:
            return {}
        if depth == 0 and char in ";\n":
            statements.append((start, index))
            start = index + 1
    calls = {}
    for begin, end in statements + [(start, len(code))]:
        statement = code[begin:end]
        # exit( is looked for in the raw text first, since a template string may call it.
        if re.search(r"(?<![\w$])exit\s*\(", script[begin:end]):
            break
        if not statement.strip():
            continue
        # A condition, loop, jump or unfinished expression may govern the following statements.
        if depth or JS_CONTROL.match(statement) or re.search(r"(?:=>|[=(,?:&|+\-*/])\s*$", statement):
            break
        call = AWAITED_CALL.match(code, begin, end)
        if not call:
            continue
        opening = call.end() - 1
        if code[opening] == "(":
            calls[opening - len("exec_command")] = script[opening:closing(code, opening) or end]
            continue
        # The array of Promise.all / allSettled: each element that is a direct call runs.
        close = closing(code, opening)
        element = opening + 1
        while close and element < close:
            direct = DIRECT_CALL.match(code, element)
            if not direct:
                break
            call_close = closing(code, direct.end() - 1)
            if call_close is None:
                break
            calls[direct.end() - len("exec_command(")] = script[direct.end() - 1:call_close + 1]
            element = call_close + 1
            separator = re.match(r"\s*,?", code[element:close])
            element += separator.end()
    return calls


def codex_commands(payload, in_memory=False):
    """(command, runs in memory) for each shell command of a Codex tool call.

    The command is None when it may read memory but cannot be read statically. `in_memory` is the
    turn's working directory; a call's own workdir replaces it, and an unreadable workdir leaves
    the directory unknown.
    """
    kind, name = payload.get("type"), payload.get("name")
    if kind == "custom_tool_call" and name == "exec":
        script = payload.get("input") or ""
        # A cmd built from variables or expressions may take its value from anywhere in the
        # script, or run in a memory working directory, so these decide whether an unreadable
        # call may read memory.
        memory_script = mentions_memory(script) or in_memory
        awaited = awaited_calls(script)
        code = JS_STRINGS.sub(lambda literal: " " * len(literal[0]), script)
        commands = []
        for match in EXEC_CALL.finditer(script):
            start = match.start()
            literal = EXEC_COMMAND.match(script, start)
            command = None
            if literal and not (literal[3] and "${" in literal[3]):
                command = js_string(next((group for group in literal.groups() if group is not None), ""))
            close = closing(code, match.end() - 1)
            arguments = script[match.end():close if close is not None else len(script)]
            workdir = WORKDIR.search(arguments)
            directory = in_memory
            value = None
            if workdir and any(group is not None for group in workdir.groups()):
                value = js_string(next(group for group in workdir.groups() if group is not None))
            # A spread anywhere in the arguments may replace cmd or workdir, and an argument that
            # is not an object literal hides both, so the call's command and directory are unknown.
            call_code = code[match.end():close if close is not None else len(code)]
            if "..." in call_code or not call_code.lstrip().startswith("{"):
                directory = None
            elif value is not None:
                directory = mentions_memory(value)
            elif workdir or (literal is None and memory_script):
                # A workdir given by an expression or an undecodable literal is unknown.
                directory = None
            if command is not None and (directory is None or start not in awaited and (mentions_memory(command) or directory)):
                command = None
            # A call in memory or in an unknown directory is kept, so its reads stay visible.
            if command is not None or memory_script or directory is not False:
                commands.append((command, bool(directory)))
        return commands
    if kind == "function_call" and name in SHELL_TOOLS:
        try:
            arguments = json.loads(payload.get("arguments") or "{}")
        except ValueError:
            return [(None, in_memory)]
        workdir = arguments.get("workdir")
        directory = mentions_memory(strings_of(workdir)) if workdir else in_memory
        return [(strings_of(arguments.get("cmd") or arguments.get("command")), directory)]
    if kind == "local_shell_call":
        action = payload.get("action") or {}
        workdir = action.get("working_directory")
        directory = mentions_memory(strings_of(workdir)) if workdir else in_memory
        return [(strings_of(action.get("command")), directory)]
    return []


def codex_events(record, state):
    payload = record.get("payload") or {}
    if record.get("type") == "turn_context":
        state["in_memory"] = mentions_memory(payload.get("cwd") or "")
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
        yield "result", payload.get("call_id"), exit_status(output), set(DELIVERED.findall(strings_of(output)))
    elif kind.endswith("call"):
        paths, lookup, own_code = set(), False, True
        commands = codex_commands(payload, state.get("in_memory", False))
        for command, in_memory in commands:
            reads = None if command is None else command_reads(command, in_memory)
            if reads is None:
                yield ("unparsed",)
                continue
            command_paths, command_lookup, command_own = reads
            paths |= command_paths
            lookup = lookup or command_lookup
            own_code = own_code and (command_own or not (command_paths or command_lookup))
        # With several commands in one call, a failing code may belong to another command.
        # write_stdin results carry exit codes too.
        calls = len(commands) + len(re.findall(r"\bwrite_stdin\s*\(", payload.get("input") or ""))
        yield "attempt", payload.get("call_id"), paths, lookup, own_code and calls <= 1


def transcripts(directories):
    for directory in directories:
        for pattern in ("*.jsonl", "*.jsonl.zst"):
            yield from glob.glob(os.path.join(directory, "**", pattern), recursive=True)


def transcript_lines(path):
    """Lines of a transcript; OSError when it cannot be read, including a compressed one without zstd."""
    if not path.endswith(".zst"):
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.readlines()
    if zstd is None:
        raise OSError(f"compression.zstd is not available for {path}")
    try:
        with zstd.open(path, "rt", encoding="utf-8", errors="replace") as handle:
            return handle.readlines()
    except (zstd.ZstdError, EOFError) as error:
        raise OSError(str(error)) from error


def build_report(repo, commit, claude_dirs, codex_dirs, since):
    tree = [path for path in git(repo, "ls-tree", "-r", "--name-only", commit).splitlines() if path.endswith(".md")]
    files = {path: {"chars": len(git(repo, "show", f"{commit}:{path}")), "retrieved": 0, "candidate": 0, "outside": 0}
             for path in tree if path not in ("MEMORY.md", "CONVENTIONS.md")}
    prompts = []
    unknown_results = unparsed_commands = unreadable = 0
    for parse, directories in ((claude_events, claude_dirs), (codex_events, codex_dirs)):
        for transcript in transcripts(directories):
            current = None
            pending, state = {}, {}
            try:
                lines = transcript_lines(transcript)
            except OSError:
                # Left out of the counts and reported, not treated as read.
                unreadable += 1
                continue
            for line in lines:
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                if record.get("timestamp", since) < since:
                    continue
                for event in parse(record, state):
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
                        pending[event[1]] = event[2:]
                    else:
                        _, call, succeeded, delivered = event
                        reads, lookup, own_code = pending.pop(call, (set(), False, True))
                        if succeeded is False and not own_code:
                            succeeded = None
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
        "unreadable_transcripts": unreadable,
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
    print("取得は、hook が動いた入力の中で実行を確かめられた `git -C <記憶 repo> show`(後のコマンドに隠れた失敗を含む)、"
          "成功した Read、lookup が渡した本文だけを数える。実行を確かめられない記憶関連のコマンドは解析不能に数えるので、"
          "取得数は記憶を読んだ回数の下限になる。"
          "サブエージェントの取得は含まない。")
    print(f"読めずに集計から外した会話記録: {report['unreadable_transcripts']} 件")
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
