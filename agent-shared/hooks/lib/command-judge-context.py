#!/usr/bin/env python3
import json
import sys
import importlib.util
import tempfile
from pathlib import Path


def message_text(content):
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ''
    return ''.join(part.get('text', '') for part in content
                   if isinstance(part, dict) and part.get('type') in ('input_text', 'output_text', 'text'))


def transcript_lines(event):
    try:
        with Path(event['transcript_path']).open(encoding='utf-8') as transcript:
            yield from transcript
    except (OSError, KeyError, TypeError):
        return


def read_messages(event):
    messages = []
    for line in transcript_lines(event):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if not isinstance(entry, dict) or entry.get('isSidechain'):
            continue
        if entry.get('type') == 'response_item':
            payload = entry.get('payload', {})
            if not isinstance(payload, dict) or payload.get('type') != 'message':
                continue
            role = payload.get('role')
            text = message_text(payload.get('content'))
        elif entry.get('type') == 'attachment':
            attachment = entry.get('attachment') or {}
            if not isinstance(attachment, dict) or attachment.get('type') != 'queued_command':
                continue
            origin = attachment.get('origin') or {}
            if not isinstance(origin, dict) or origin.get('kind') not in (None, 'human'):
                continue
            role, text = 'user', attachment.get('prompt', '')
        else:
            role = entry.get('type')
            payload = entry.get('message') or {}
            if not isinstance(payload, dict):
                continue
            content = payload.get('content')
            if role == 'user':
                origin = entry.get('origin') or {}
                if (entry.get('isMeta') or entry.get('isCompactSummary')
                        or not isinstance(origin, dict) or origin.get('kind') not in (None, 'human')
                        or isinstance(content, list) and any(isinstance(p, dict) and p.get('type') == 'tool_result' for p in content)):
                    continue
            text = message_text(content)
        if role in ('user', 'assistant') and isinstance(text, str) and text:
            messages.append((role, text, entry.get('timestamp')))
    return messages


def prior_messages(event):
    messages = read_messages(event)
    prompt = event.get('prompt')
    if (messages and isinstance(prompt, str) and messages[-1][0] == 'user'
            and messages[-1][1].rstrip('\n') == prompt.rstrip('\n')):
        messages.pop()
    return messages


def assistant_tail(messages):
    start = next((i + 1 for i in range(len(messages) - 1, -1, -1) if messages[i][0] == 'user'), 0)
    return '\n\n'.join(text for role, text, _ in messages[start:] if role == 'assistant')


def conversation_context(event):
    return {'current_transcript': [
        {'role': role, 'text': text, 'timestamp': timestamp}
        for role, text, timestamp in read_messages(event)]}


def mask_context(text):
    source = Path(__file__).resolve().parents[2] / 'bin/output-gate-check.py'
    spec = importlib.util.spec_from_file_location('output_gate_check', source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory(prefix='command-judge-context-') as folder:
        return module.mask_secrets(text, Path(folder))


def main():
    event = json.load(sys.stdin.buffer)
    if len(sys.argv) >= 2 and sys.argv[1] == '--context':
        text = conversation_context(event)
        if '--mask' in sys.argv[2:]:
            text = mask_context(text)
        sys.stdout.buffer.write(json.dumps(text, ensure_ascii=False).encode('utf-8'))
    else:
        sys.stdout.buffer.write(assistant_tail(prior_messages(event)).encode('utf-8'))


try:
    main()
except (OSError, ValueError, TypeError, KeyError, AttributeError):
    if '--context' in sys.argv[1:]:
        sys.exit(1)
