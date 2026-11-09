#!/usr/bin/env python3
"""Read typed Codex session evidence without persisting a cursor or private reasoning.

collect_session returns (source_rows, next_cursor). The caller commits next_cursor
only after importing the returned rows. Cursor values contain locators and IDs,
not command output, user task text, or agent reports.
"""
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path
import re


_SAFE_ID = re.compile(r'[A-Za-z0-9_.-]{1,160}\Z')
_TEXT_TYPES = {'text', 'Text', 'input_text', 'output_text'}
_PRIMARY = {'CommandExecution', 'McpToolCall', 'FileChange'}


def _json(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def _text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return ''.join(block['text'] for block in content if isinstance(block, dict)
                       and block.get('type') in _TEXT_TYPES and isinstance(block.get('text'), str))
    return ''


def _record_at(path, offset):
    with path.open('rb') as stream:
        stream.seek(offset)
        line = stream.readline()
    if not line.endswith(b'\n'):
        return None
    try:
        value = json.loads(line)
        return value if isinstance(value, dict) else None
    except (ValueError, UnicodeError):
        return None


def _item(record):
    payload = record.get('payload')
    if not isinstance(payload, dict):
        return None
    if record.get('type') == 'event_msg' and payload.get('type') in ('item_started', 'item_completed', 'item_updated'):
        item = payload.get('item')
        return item if isinstance(item, dict) else None
    if record.get('type') == 'response_item' and payload.get('type') == 'message' and payload.get('role') == 'assistant' and payload.get('phase') == 'final_answer':
        return {'type': 'AgentMessage', 'id': payload.get('id'), 'content': payload.get('content'), 'phase': 'final_answer'}
    if record.get('type') == 'response_item' and payload.get('type') == 'agent_message':
        return {'type': 'AgentCallback', **{key: payload.get(key) for key in ('id', 'author', 'recipient', 'content')}}
    if record.get('type') == 'response_item' and payload.get('type') == 'function_call' and payload.get('namespace') == 'collaboration' and payload.get('name') == 'spawn_agent':
        arguments = payload.get('arguments')
        if isinstance(arguments, str):
            try:
                arguments = json.loads(arguments)
            except ValueError:
                return None
        if isinstance(arguments, dict):
            return {'type': 'SpawnAgentCall', 'id': payload.get('call_id'),
                    'role': {key: arguments[key] for key in ('agent_type', 'task_name', 'model', 'reasoning_effort', 'fork_turns')
                             if isinstance(arguments.get(key), str)}}
    return None


def _encrypted(item):
    content = item.get('content')
    return isinstance(content, list) and any(
        isinstance(block, dict) and block.get('type') == 'encrypted_content' for block in content)


def _inbound(item, scope):
    path = scope.get('agent_path', '')
    return (item.get('type') == 'AgentCallback' and bool(path)
            and item.get('recipient') == path and item.get('author') == path.rpartition('/')[0])


def _turn(record, fallback=''):
    payload = record.get('payload') or {}
    passthrough = payload.get('internal_chat_message_metadata_passthrough') or {}
    return payload.get('turn_id') or passthrough.get('turn_id') or fallback


def _metadata(sid, record, item, scope):
    metadata = {'producer_session_id': sid, 'native_event_id': item.get('id'),
                'native_event_type': item['type'], 'native_record_type': record.get('type'),
                'timestamp': record.get('timestamp', '')}
    metadata.update(scope)
    return metadata


def _source(sid, ident, turn, call, output, metadata):
    return {'kind': 'evidence', 'native_id': f'codex-native:{sid}:{ident}', 'turn_id': turn,
            'fields': {'call': _json(call), 'output': output, 'metadata': _json(metadata)},
            'metadata': metadata, 'available': True, 'producer_truncated': False}


def _gap(sid, reason, token, timestamp=''):
    ident = hashlib.sha256(str(token).encode()).hexdigest()[:24]
    metadata = {'producer_session_id': sid, 'native_event_type': 'collector_gap', 'timestamp': timestamp}
    return {'kind': 'gap', 'native_id': f'codex-native:{sid}:gap:{ident}', 'turn_id': '',
            'fields': {'text': reason, 'metadata': _json(metadata)}, 'metadata': metadata, 'available': False}


def _failed(status, code=None, is_error=None):
    if status in ('failed', 'cancelled', 'canceled', 'interrupted') or is_error is True or isinstance(code, int) and not isinstance(code, bool) and code != 0:
        return True
    if status in ('completed', 'succeeded', 'success'):
        return False
    return None


def _primary(sid, record, item, turn, scope):
    typ = item['type']
    metadata = _metadata(sid, record, item, scope)
    status = item.get('status')
    metadata['status'] = status
    if typ == 'CommandExecution':
        call = {'tool': typ, **{key: item[key] for key in ('command', 'cwd', 'process_id', 'source', 'parsed_cmd') if key in item}}
        output = item.get('aggregated_output')
        output = output if isinstance(output, str) else ''
        metadata['exit_code'] = item.get('exit_code')
        metadata['failed'] = _failed(status, item.get('exit_code'))
        if metadata['failed'] is False and not isinstance(item.get('exit_code'), int):
            metadata['failed'] = None
    elif typ == 'McpToolCall':
        call = {'tool': item.get('tool'), 'server': item.get('server'), 'arguments': item.get('arguments')}
        result = item.get('result')
        output = _json(result) if result is not None else ''
        is_error = result.get('isError') if isinstance(result, dict) else None
        metadata.update({'isError': is_error, 'failed': _failed(status, is_error=is_error)})
        if 'error' in item:
            metadata['error'] = item['error']
            if item['error'] is not None:
                metadata['failed'] = True
    else:
        call = {'tool': typ}
        output = _json({key: item[key] for key in ('changes', 'stdout', 'stderr') if key in item})
        metadata['failed'] = _failed(status)
    if 'duration' in item:
        metadata['duration'] = item['duration']
    return _source(sid, item['id'], turn, call, output, metadata)


def collect_session(session_id, codex_home=None, cursor=None):
    """Collect only a named session and explicitly linked children, incrementally.

    A first missing root session returns no rows, allowing raw API fallback.
    Missing previously observed files, resets, malformed rows and mismatched
    session metadata produce unavailable gap rows rather than success evidence.
    """
    if not isinstance(session_id, str) or not _SAFE_ID.fullmatch(session_id) or session_id in ('.', '..'):
        raise ValueError('invalid Codex session id')
    home = Path(codex_home) if codex_home is not None else Path.home() / '.codex'
    root = home / 'sessions'
    previous = deepcopy(cursor) if isinstance(cursor, dict) else {}
    state = previous if previous.get('session_id') == session_id and previous.get('version') == 1 else {
        'version': 1, 'session_id': session_id, 'sessions': {}}
    sessions = state.setdefault('sessions', {})
    rows = {}
    gap_ids = set(state.get('gap_ids', []))
    visited = set()
    active = set()
    changed = {}

    def add(row):
        if row['kind'] == 'gap':
            if row['native_id'] in gap_ids:
                return
            gap_ids.add(row['native_id'])
        rows[(row['kind'], row['native_id'])] = row

    def locate(sid, saved):
        if saved.get('path'):
            path = Path(saved['path'])
            try:
                path.resolve().relative_to(root.resolve())
            except ValueError:
                return None, 'Session locator is outside the sessions directory.'
            if not path.is_file():
                return None, 'Previously observed Codex session file is unavailable.'
            return path, None
        candidates = sorted(root.rglob('*' + sid + '*.jsonl')) if root.is_dir() else []
        mismatch = False
        for path in candidates:
            try:
                first = _record_at(path, 0)
            except OSError:
                continue
            payload = first.get('payload') if first else None
            if isinstance(payload, dict) and first.get('type') == 'session_meta':
                if payload.get('id') == sid:
                    return path, None
                mismatch = True
        return None, 'Codex session metadata does not match the requested session.' if mismatch else None

    def pointers(saved, name, path):
        result = []
        for pointer in saved.get(name, []):
            record = _record_at(path, pointer['offset'])
            item = _item(record) if record else None
            if item and item.get('id') == pointer['id']:
                result.append((pointer, record, item))
        return result

    def read(sid, scope=None, linked=False):
        scope = scope or {}
        if sid in active or sid in visited:
            return changed.get(sid, False)
        active.add(sid)
        visited.add(sid)
        old = sessions.get(sid, {})
        path, error = locate(sid, old)
        if path is None:
            if error or linked:
                add(_gap(sid, error or 'Explicitly linked child session is unavailable.', [old.get('path'), error, sid]))
            active.remove(sid)
            changed[sid] = False
            return False
        try:
            with path.open('rb') as stream:
                stat = os.fstat(stream.fileno())
                identity = [stat.st_dev, stat.st_ino]
                first = _record_at(path, 0)
                meta = first.get('payload') if first else None
                if not isinstance(meta, dict) or first.get('type') != 'session_meta' or meta.get('id') != sid:
                    add(_gap(sid, 'Codex session metadata does not match the requested session.', [str(path), identity, stat.st_mtime_ns]))
                    active.remove(sid)
                    changed[sid] = False
                    return False
                offset = old.get('offset', 0)
                anchor_changed = False
                if old.get('anchor_hash') and isinstance(old.get('anchor_offset'), int):
                    stream.seek(old['anchor_offset'])
                    anchor_changed = hashlib.sha256(stream.readline()).hexdigest() != old['anchor_hash']
                reset = old and (old.get('identity') != identity or not isinstance(offset, int) or offset > stat.st_size or anchor_changed)
                if reset:
                    add(_gap(sid, 'Codex session identity changed or its cursor exceeds the file size.', [identity, stat.st_mtime_ns]))
                    old, offset = {}, 0
                saved = deepcopy(old)
                saved.update({'path': str(path), 'identity': identity, 'offset': offset})
                saved.setdefault('links', {})
                saved.setdefault('spawn_roles', {})
                saved.setdefault('tasks', [])
                saved.setdefault('finals', [])
                saved.setdefault('item_turns', {})
                turn = saved.get('turn_id', '')
                new_events = []
                new_spawn_ids = set()
                stream.seek(offset)
                while True:
                    start = stream.tell()
                    line = stream.readline()
                    if not line or not line.endswith(b'\n'):
                        break
                    saved['offset'] = stream.tell()
                    saved['anchor_offset'] = start
                    saved['anchor_hash'] = hashlib.sha256(line).hexdigest()
                    try:
                        record = json.loads(line)
                    except (ValueError, UnicodeError):
                        add(_gap(sid, 'Codex session row is not valid JSON.', [identity, start]))
                        continue
                    if not isinstance(record, dict):
                        continue
                    turn = _turn(record, turn)
                    item = _item(record)
                    if not item or item.get('type') not in _PRIMARY | {'SubAgentActivity', 'UserMessage', 'AgentMessage', 'AgentCallback', 'SpawnAgentCall'} or not isinstance(item.get('id'), str):
                        continue
                    ident = item['id']
                    item_turn = saved['item_turns'].setdefault(ident, turn)
                    pointer = {'id': ident, 'offset': start, 'turn_id': item_turn}
                    typ = item['type']
                    if typ == 'SpawnAgentCall':
                        saved['spawn_roles'][ident] = item['role']
                        new_spawn_ids.add(ident)
                    elif typ == 'SubAgentActivity':
                        link = saved['links'].setdefault(ident, {})
                        link.update(pointer)
                        link['owner'] = link.get('owner', False) or item.get('kind') == 'started'
                        for key in ('model', 'reasoning_effort', 'agent_thread_id', 'agent_path'):
                            if item.get(key) is not None:
                                link[key] = item[key]
                    elif linked and (typ == 'UserMessage' or _inbound(item, scope)):
                        saved['tasks'] = [p for p in saved['tasks'] if p['id'] != ident] + [pointer]
                    elif typ == 'AgentMessage' and linked and item.get('phase') == 'final_answer':
                        saved['finals'] = [p for p in saved['finals'] if p['id'] != ident] + [pointer]
                    elif typ in _PRIMARY or typ == 'AgentCallback':
                        new_events.append((record, item, item_turn, start))
                saved['turn_id'] = turn
            task_rows = pointers(saved, 'tasks', path)
            final_rows = pointers(saved, 'finals', path)
            def task_scope(position):
                prior = [(p, i) for p, _, i in task_rows if p['offset'] <= position]
                latest = max(prior, key=lambda pair: pair[0]['offset']) if prior else None
                return {**scope,
                        'task_scope_ids': [f"codex-native:{sid}:{latest[0]['id']}"] if latest else []}
            for record, item, item_turn, position in new_events:
                event_scope = task_scope(position) if linked else scope
                if item['type'] == 'AgentCallback':
                    metadata = _metadata(sid, record, item, event_scope)
                    metadata.update({key: item.get(key) for key in ('author', 'recipient')})
                    metadata['encrypted_content_omitted'] = _encrypted(item)
                    callback = _source(sid, item['id'], item_turn,
                                {'tool': 'agent_message', 'author': item.get('author'), 'recipient': item.get('recipient')},
                                _text(item.get('content')), metadata)
                    callback['producer_truncated'] = _encrypted(item)
                    add(callback)
                else:
                    add(_primary(sid, record, item, item_turn, event_scope))
            own_changed = saved['offset'] != old.get('offset', 0) or bool(reset)
            if linked and own_changed:
                for pointer, record, item in [*task_rows, *final_rows]:
                    if pointer['offset'] < offset and not reset:
                        continue
                    report_scope = task_scope(pointer['offset'])
                    metadata = _metadata(sid, record, item, report_scope)
                    metadata['phase'] = item.get('phase')
                    metadata['encrypted_content_omitted'] = _encrypted(item)
                    is_task = item['type'] == 'UserMessage' or _inbound(item, scope)
                    if is_task:
                        metadata.update({'context_kind': 'delegated_task', 'displayed': False,
                                         'task_scope_available': bool(_text(item.get('content'))) and not _encrypted(item)})
                        source = {'kind': 'assistant', 'native_id': f"codex-native:{sid}:{item['id']}",
                                  'turn_id': pointer['turn_id'],
                                  'fields': {'text': _text(item.get('content')), 'metadata': _json(metadata)},
                                  'metadata': metadata, 'available': True, 'producer_truncated': _encrypted(item)}
                    else:
                        source = _source(sid, item['id'], pointer['turn_id'],
                                         {'tool': 'delegated_report', **report_scope}, _text(item.get('content')), metadata)
                        source['producer_truncated'] = _encrypted(item)
                    add(source)
            child_roles = {link.get('agent_thread_id'): {**saved['spawn_roles'][ident], 'spawn_call_id': ident}
                           for ident, link in saved['links'].items() if ident in saved['spawn_roles']}
            for ident, link in saved['links'].items():
                child = link.get('agent_thread_id')
                if not isinstance(child, str) or not _SAFE_ID.fullmatch(child) or child in ('.', '..'):
                    continue
                owner = link.get('owner', False) or ident in saved['spawn_roles']
                if owner:
                    provenance = {**child_roles.get(child, {}), **saved['spawn_roles'].get(ident, {}),
                                  'parent_session_id': sid, 'parent_event_id': ident, 'agent_thread_id': child,
                                  **{k: link[k] for k in ('model', 'reasoning_effort', 'agent_path') if k in link}}
                    read(child, provenance, linked=True)
                else:
                    provenance = {'activity_relation': 'interaction', 'agent_thread_id': child,
                                  **{k: link[k] for k in ('model', 'reasoning_effort', 'agent_path') if k in link}}
                if link['offset'] >= offset or ident in new_spawn_ids or reset:
                    record = _record_at(path, link['offset'])
                    item = _item(record) if record else None
                    if not item:
                        continue
                    metadata = _metadata(sid, record, item, provenance)
                    metadata['status'] = item.get('kind')
                    call = {'tool': 'SubAgentActivity', **provenance}
                    output = _json({key: item[key] for key in (
                        'kind', 'model', 'reasoning_effort', 'agent_thread_id', 'agent_path') if key in item})
                    add(_source(sid, ident, link['turn_id'], call, output, metadata))
            sessions[sid] = saved
            changed[sid] = own_changed
        except (OSError, ValueError, TypeError) as error:
            add(_gap(sid, 'Codex session could not be read (' + type(error).__name__ + ').', [str(path), type(error).__name__]))
            changed[sid] = False
        active.remove(sid)
        return changed[sid]

    read(session_id)
    state['gap_ids'] = sorted(gap_ids)
    return sorted(rows.values(), key=lambda row: row['metadata'].get('timestamp', '')), state
