#!/usr/bin/env python3
import hashlib
import json
import sys
from pathlib import Path


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode()).hexdigest()


def journal(path):
    if not path.exists():
        return []
    if path.is_symlink():
        raise ValueError('symlink journal')
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    for row in rows:
        if (not isinstance(row, dict) or not isinstance(row.get('text'), str)
                or not isinstance(row.get('assistant_context', ''), str)):
            raise ValueError('invalid journal')
    return rows


def sources(rows):
    return [f'{i + 1}:{digest(row)}' for i, row in enumerate(rows)]


def valid_facts(facts, refs):
    if not isinstance(facts, list):
        return False
    for fact in facts:
        if (not isinstance(fact, dict)
                or set(fact) != {'sources', 'purpose', 'target', 'effect', 'scope', 'status'}
                or not all(isinstance(fact[key], str) for key in ('purpose', 'target', 'effect', 'scope'))
                or fact['status'] not in ('allowed', 'denied', 'pending')
                or not isinstance(fact['sources'], list) or not fact['sources']
                or not all(isinstance(ref, str) and ref in refs for ref in fact['sources'])):
            return False
    return True


def valid_state(state, rows, policy, current=False):
    if (not isinstance(state, dict)
            or set(state) != {'version', 'policy', 'count', 'revision', 'facts'}
            or type(state['version']) is not int or state['version'] != 1
            or state['policy'] != policy or type(state['count']) is not int
            or not 0 <= state['count'] <= len(rows)):
        return False
    count = state['count']
    return ((not current or count == len(rows)) and state['revision'] == digest(rows[:count])
            and valid_facts(state['facts'], sources(rows[:count])))


def main():
    mode, journal_path, state_path, policy = sys.argv[1:]
    rows = journal(Path(journal_path))
    if mode == 'verify':
        evaluated = json.load(sys.stdin)
        sys.exit(0 if valid_state(evaluated, rows, policy, current=True) else 1)
    state = None
    path = Path(state_path)
    if path.is_file() and not path.is_symlink():
        try:
            state = json.loads(path.read_text())
        except (ValueError, OSError):
            pass
    if mode == 'prepare':
        if not valid_state(state, rows, policy):
            state = {'version': 1, 'policy': policy, 'count': 0, 'revision': digest([]), 'facts': []}
        start = state['count']
        result = {'revision': digest(rows), 'count': len(rows), 'previous': state['facts'],
                  'new_inputs': [{'ref': ref, 'input': row['text'],
                                  'input_context': row.get('assistant_context', '')}
                                 for row, ref in zip(rows[start:], sources(rows)[start:])]}
    elif mode == 'finish':
        request = json.load(sys.stdin)
        update, answer = request['update'], request['answer']
        if (type(update['count']) is not int or update['count'] != len(rows)
                or update['revision'] != digest(rows) or not isinstance(answer, dict)
                or set(answer) != {'facts'} or not valid_facts(answer['facts'], sources(rows))):
            raise ValueError('invalid state or changed journal')
        result = {'version': 1, 'policy': policy, 'count': len(rows),
                  'revision': digest(rows), 'facts': answer['facts']}
    else:
        raise ValueError('unknown mode')
    print(json.dumps(result, ensure_ascii=False, separators=(',', ':')))


try:
    main()
except (ValueError, OSError, TypeError, KeyError):
    sys.exit(1)
