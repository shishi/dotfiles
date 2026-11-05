#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def main():
    event = json.load(sys.stdin.buffer)
    path = Path(event['transcript_path'])
    prompt = event.get('prompt', '')
    messages = []
    with path.open('rb') as transcript:
        size = transcript.seek(0, 2)
        transcript.seek(max(0, size - 2_000_000))
        if size > 2_000_000:
            transcript.readline()
        for line in transcript:
            entry = json.loads(line)
            payload = entry.get('payload', {})
            if entry.get('type') != 'response_item' or payload.get('type') != 'message':
                continue
            role = payload.get('role')
            if role not in ('user', 'assistant'):
                continue
            content = payload.get('content', [])
            text = ''.join(part.get('text', '') for part in content
                           if isinstance(part, dict) and part.get('type') in ('input_text', 'output_text'))
            messages.append((role, payload.get('phase'), text))
    if messages and messages[-1][0] == 'user' and messages[-1][2].rstrip('\n') == prompt.rstrip('\n'):
        messages.pop()
    if messages and messages[-1][0:2] == ('assistant', 'final_answer'):
        text = messages[-1][2]
        if len(text) <= 4000:
            sys.stdout.buffer.write(text.encode('utf-8'))
        else:
            sys.exit(3)


try:
    main()
except (OSError, ValueError, TypeError, KeyError, AttributeError):
    pass
