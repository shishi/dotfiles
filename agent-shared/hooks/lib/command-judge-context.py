#!/usr/bin/env python3
import json
import sys
import importlib.util
import hashlib
import os
import stat
from contextlib import contextmanager
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


def transcript_entries(event):
    for line in transcript_lines(event):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict) and not entry.get('isSidechain'):
            yield entry


def read_messages(event, entries=None):
    messages = []
    for entry in transcript_entries(event) if entries is None else entries:
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


def tool_evidence(event, request, entries=None, masker=None):
    records = []
    for entry in transcript_entries(event) if entries is None else entries:
        payload = entry.get('payload', {})
        if entry.get('type') == 'response_item' and isinstance(payload, dict) and payload.get('type') != 'message':
            records.append(payload)
        elif entry.get('type') in ('assistant', 'user'):
            content = (entry.get('message') or {}).get('content', [])
            if isinstance(content, list):
                records.extend(p for p in content if isinstance(p, dict) and p.get('type') in ('tool_use', 'tool_result'))
    if masker is not None and records:
        records = masker(records)
    index, selected, available = [], [], set()
    query = request.get('query', '')
    wanted = request.get('records', [])
    include_index = request.get('index', not (wanted or request.get('files')))
    if not isinstance(query, str) or not isinstance(wanted, list) or type(include_index) is not bool:
        raise ValueError('invalid evidence request')
    include_index = bool(query) or include_index
    for i, record in enumerate(records):
        raw = json.dumps(record, ensure_ascii=False, sort_keys=True)
        ref = f'tool:{i}:{hashlib.sha256(raw.encode()).hexdigest()}'
        available.add(ref)
        text = record.get('output', record.get('arguments', record.get('input', record.get('content', ''))))
        if not isinstance(text, str):
            text = json.dumps(text, ensure_ascii=False)
        if include_index and (not query or query.casefold() in raw.casefold()):
            index.append({'ref': ref, 'type': record.get('type'), 'name': record.get('name'),
                          'characters': len(raw), 'preview': text[:200]})
        for item in wanted:
            spec = {'ref': item} if isinstance(item, str) else item
            if not isinstance(spec, dict) or not isinstance(spec.get('ref'), str):
                raise ValueError('invalid record request')
            if spec['ref'] != ref:
                continue
            start = spec.get('start', 0)
            # Reserve space under the CLI's 1 MiB character limit for other evidence and policy.
            end = spec.get('end', min(len(raw), start + 262144)) if type(start) is int else None
            if type(start) is not int or type(end) is not int or not 0 <= start <= end <= len(raw):
                raise ValueError('invalid evidence range')
            receipt = {'ref': ref, 'characters': len(raw), 'start': start, 'end': end,
                       'complete': start == 0 and end == len(raw)}
            if receipt['complete']:
                receipt['content'] = record
            else:
                receipt['excerpt'] = raw[start:end]
            selected.append(receipt)
    missing = [item.get('ref') if isinstance(item, dict) else item for item in wanted
               if (item.get('ref') if isinstance(item, dict) else item) not in available]
    return {'tool_index': index, 'tool_records': selected, 'tool_record_count': len(records), 'tool_index_available': True,
            'unavailable_records': missing}


def file_evidence(event, request, masker=None):
    cwd = Path(event.get('context_cwd') or event.get('cwd') or '.').resolve()
    root = next((p for p in (cwd, *cwd.parents) if (p / '.git').exists()), cwd)
    result, specs = [], []
    wanted = request.get('files', [])
    if not isinstance(wanted, list):
        raise ValueError('invalid file request')
    for item in wanted:
        spec = {'path': item} if isinstance(item, str) else item
        if not isinstance(spec, dict) or not isinstance(spec.get('path'), str):
            raise ValueError('invalid file request')
        start = spec.get('start', 0)
        end = spec.get('end', start + 262144) if type(start) is int else None
        if type(start) is not int or type(end) is not int or not 0 <= start <= end or end - start > 262144:
            raise ValueError('invalid file range')
        specs.append((spec, (cwd / spec['path']).resolve(), start, end))
    sources = {}
    for path in dict.fromkeys(path for _, path, _, _ in specs):
        try:
            if root != path and root not in path.parents:
                raise ValueError('outside the current project')
            ranges = [(a, b) for _, p, a, b in specs if p == path]
            data = bytearray()
            fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NONBLOCK', 0) | getattr(os, 'O_NOFOLLOW', 0))
            try:
                info = os.fstat(fd)
                if not stat.S_ISREG(info.st_mode):
                    raise ValueError('not a regular source file')
                # At most four UTF-8 bytes can represent one CLI input character.
                if info.st_size > 4 * 1048576:
                    raise ValueError('source exceeds the bounded evidence snapshot')
                while True:
                    raw = os.read(fd, 65536)
                    if not raw:
                        break
                    data.extend(raw)
                    if len(data) > 4 * 1048576:
                        raise ValueError('source exceeds the bounded evidence snapshot')
            finally:
                os.close(fd)
            text = bytes(data).decode('utf-8')
            digest = hashlib.sha256(data).hexdigest()
            # Mask the complete source before ranges so a secret cannot straddle excerpts.
            view = masker(text) if masker is not None else text
            sources[path] = (digest, len(view), {(a, b): view[a:b] for a, b in ranges}, None)
        except (OSError, UnicodeError, ValueError) as error:
            sources[path] = (None, 0, {}, str(error))
    for spec, path, start, end in specs:
        receipt = {'path': spec['path']}
        digest, count, excerpts, error = sources[path]
        try:
            if error is not None:
                raise ValueError(error)
            if start > count:
                raise ValueError('invalid file range')
            receipt.update(sha256=digest, characters=count, start=start, end=min(end, count),
                           complete=start == 0 and end >= count, content=excerpts[(start, end)])
        except (OSError, UnicodeError, ValueError) as error:
            receipt['unavailable'] = str(error)
        result.append(receipt)
    return result


def conversation_context(event, journal_path=None, masker=None):
    request = event.get('context_request', {})
    if not isinstance(request, dict):
        raise ValueError('invalid context request')
    include_conversation = request.get('conversation', not bool(request.get('files')))
    include_index = request.get('index', not (request.get('files') or request.get('records')))
    if type(include_conversation) is not bool or type(include_index) is not bool:
        raise ValueError('invalid context request')
    need_records = include_index or bool(request.get('query') or request.get('records'))
    entries = list(transcript_entries(event)) if journal_path or include_conversation or need_records else []
    messages = read_messages(event, entries) if journal_path or include_conversation else []
    if journal_path:
        try:
            rows = [json.loads(line) for line in Path(journal_path).read_text().splitlines() if line.strip()]
            remaining, assistant, cursor = [], [], 0
            for message in messages:
                role, text, _ = message
                if role == 'assistant':
                    assistant.append(message)
                    continue
                context = '\n\n'.join(item[1] for item in assistant)
                matched = next((i for i in range(cursor, len(rows))
                                if rows[i]['text'] == text and rows[i].get('assistant_context', '') == context), None)
                if matched is None:
                    remaining.extend(assistant)
                    remaining.append(message)
                else:
                    cursor = matched + 1
                assistant = []
            messages = remaining
        except (OSError, ValueError, TypeError, KeyError, AttributeError):
            pass
    result = {'current_transcript': [
        {'role': role, 'text': text, 'timestamp': timestamp}
        for role, text, timestamp in messages]}
    if not journal_path:
        result.update(tool_evidence(event, request, entries, masker) if need_records else {
            'tool_index': [], 'tool_records': [], 'tool_record_count': None, 'tool_index_available': True})
        result['files'] = file_evidence(event, request, masker)
    return result


@contextmanager
def masking_session():
    source = Path(__file__).resolve().parents[2] / 'bin/output-gate-check.py'
    spec = importlib.util.spec_from_file_location('output_gate_check', source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory(prefix='command-judge-context-') as folder:
        yield lambda text: module.mask_secrets(text, Path(folder))


def main():
    event = json.load(sys.stdin.buffer)
    if len(sys.argv) >= 2 and sys.argv[1] == '--verify-files':
        previous = event.get('context_files', [])
        current = file_evidence(event, {'files': [r['path'] for r in previous]})
        sys.exit(0 if [r.get('sha256') for r in current] == [r.get('sha256') for r in previous] else 1)
    elif len(sys.argv) >= 2 and sys.argv[1] == '--context':
        journal_path = sys.argv[sys.argv.index('--since') + 1] if '--since' in sys.argv else None
        with masking_session() as mask:
            text = conversation_context(event, journal_path, mask)
            if '--mask' in sys.argv[2:] or text.get('files'):
                text = mask(text)
        sys.stdout.buffer.write(json.dumps(text, ensure_ascii=False).encode('utf-8'))
    else:
        sys.stdout.buffer.write(assistant_tail(prior_messages(event)).encode('utf-8'))


try:
    main()
except (OSError, ValueError, TypeError, KeyError, AttributeError):
    if '--context' in sys.argv[1:]:
        sys.exit(1)
