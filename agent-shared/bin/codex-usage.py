#!/usr/bin/env python3
"""Read account quota via the authenticated Codex stdio app-server RPC."""
import datetime
from decimal import Decimal, InvalidOperation
import json
import os
import re
import selectors
import subprocess
import time


def quota_snapshot(value):
    """Keep quota fields; never forward account data or raw server messages."""
    if not isinstance(value, dict):
        return None
    result = {}
    for name in ('primary', 'secondary'):
        window = value.get(name)
        if isinstance(window, dict):
            result[name] = {key: item for key, item in window.items()
                            if key in ('usedPercent', 'windowDurationMins', 'resetsAt')
                            and type(item) in (int, float)}
        elif window is None and name in value:
            result[name] = None
    credits = value.get('credits')
    if isinstance(credits, dict):
        result['credits'] = {key: credits[key] for key in ('hasCredits', 'unlimited')
                             if type(credits.get(key)) is bool}
        # The RPC schema exposes the credit balance as a decimal string or null.
        balance = credits.get('balance')
        if balance is None:
            result['credits']['balance'] = None
        elif isinstance(balance, str):
            try:
                if Decimal(balance).is_finite():
                    result['credits']['balance'] = balance
            except InvalidOperation:
                pass
    return result if any(result.get(key) for key in ('primary', 'secondary', 'credits')) else None


def read_rate_limits(timeout=30):
    """Return sanitized observation and exit code; reap the server on every path."""
    observed = {'observed_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'status': 'unknown', 'rate_limits': None}
    process = None
    selector = selectors.DefaultSelector()
    deadline = time.monotonic() + timeout
    pending = b''
    try:
        process = subprocess.Popen(['codex', 'app-server'], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        selector.register(process.stdout, selectors.EVENT_READ)

        def send(message):
            process.stdin.write((json.dumps(message) + '\n').encode())
            process.stdin.flush()

        def response(request_id):
            nonlocal pending
            while True:
                while b'\n' in pending:
                    line, pending = pending.split(b'\n', 1)
                    message = json.loads(line)
                    if not isinstance(message, dict):
                        raise ValueError('invalid RPC message')
                    if 'method' in message:
                        if 'id' in message:
                            send({'id': message['id'], 'error': {
                                'code': -32601, 'message': 'Method not supported'}})
                        continue
                    if message.get('id') == request_id:
                        if 'error' in message or 'result' not in message:
                            raise ValueError('RPC failed')
                        return message['result']
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    raise TimeoutError
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    raise EOFError
                pending += chunk

        send({'id': 1, 'method': 'initialize', 'params': {
            'clientInfo': {'name': 'agent-usage', 'version': '1.0'},
            'capabilities': {'experimentalApi': True}}})
        response(1)
        send({'method': 'initialized', 'params': {}})
        send({'id': 2, 'method': 'account/rateLimits/read', 'params': {}})
        result = response(2)
        limits = quota_snapshot(result.get('rateLimits')) if isinstance(result, dict) else None
        buckets = result.get('rateLimitsByLimitId') if isinstance(result, dict) else None
        by_id = {}
        if isinstance(buckets, dict):
            for key, bucket in buckets.items():
                # Public metered Codex slugs only; account/reset-credit IDs are not bucket names.
                if (re.fullmatch(r'codex(?:[_-][a-z0-9]+)*', key)
                        and isinstance(bucket, dict) and bucket.get('limitId') == key):
                    snapshot = quota_snapshot(bucket)
                    if snapshot is not None:
                        by_id[key] = snapshot
        if by_id:
            observed['rate_limits_by_id'] = by_id
        if limits is not None or by_id:
            observed.update(observed_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                            status='ok', rate_limits=limits)
    except (OSError, ValueError, TimeoutError, EOFError):
        pass
    finally:
        selector.close()
        if process is not None:
            if process.poll() is None:
                process.terminate()
            try:
                process.wait(timeout=max(0, min(0.2, deadline - time.monotonic())))
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            try:
                process.stdin.close()
            except BrokenPipeError:
                pass
            finally:
                process.stdout.close()
    return observed, 0 if observed['status'] == 'ok' else 1


if __name__ == '__main__':
    observation, exit_code = read_rate_limits()
    print(json.dumps(observation, separators=(',', ':')))
    raise SystemExit(exit_code)
