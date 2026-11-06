#!/usr/bin/env python3
"""出力ゲートが Codex の config.toml に書くマシン固有の行を、足す・外す。

  output-gate-codex-config.py apply --port N <config.toml>   中継へ向ける行と機能フラグの行を書く
  output-gate-codex-config.py remove <config.toml>           それらの行を外す
  output-gate-codex-config.py smudge                         Git の smudge フィルター: 標準入力の内容に、
                                                             有効なマシンなら行を足して標準出力へ出す

書く行:
  openai_base_url = "http://127.0.0.1:N/backend-api/codex"   (最初の表より前)
  [features] の token_budget / context_management / output_token_replay / enable_request_compression = false

変わったら changed、変わらなければ unchanged を出力する。共有の codex/config.toml では、
Git の clean フィルター (clean-codex-config.sh) が同じ行を除くため、これらの行は追跡されない。
行単位で編集し、ほかの行の書式・コメント・改行コードを変えない。編集した結果は TOML として読み直し、
意図した値以外が変わる場合は書かずに 1 で終える。

smudge は、pull や checkout が作業コピーの config.toml を書くときに行を戻す。中継を使うかとポートは、
hook と同じ状態ファイル ($XDG_STATE_HOME/output-gate/codex.json) を読む。Codex は起動時に設定を読むため、
行が消えた間に起動したセッションは中継を通らない。その間を作らないためにここで戻す。どんな失敗でも
入力をそのまま出す (Git の書き出しを止めない)。
"""
import argparse
import copy
import os
from pathlib import Path
import json
import re
import sys

FEATURE_KEYS = ('token_budget', 'context_management', 'output_token_replay', 'enable_request_compression')
BASE_KEY = 'openai_base_url'
TABLE = re.compile(r'^\s*\[')
FEATURES_HEADER = re.compile(r'^\s*\[features\]\s*(#.*)?$')


def key_of(line):
    match = re.match(r'^\s*([A-Za-z0-9_-]+)\s*=', line)
    return match.group(1) if match else None


def remove_lines(lines):
    out, table = [], None
    for line in lines:
        if TABLE.match(line):
            table = 'features' if FEATURES_HEADER.match(line) else 'other'
        key = key_of(line)
        if (table is None and key == BASE_KEY) or (table == 'features' and key in FEATURE_KEYS):
            continue
        out.append(line)
    return out


def apply_lines(lines, port):
    lines = remove_lines(lines)
    if not any(FEATURES_HEADER.match(line) for line in lines):
        if lines and lines[-1].strip():
            lines.append('')
        lines.append('[features]')
    base = f'{BASE_KEY} = "http://127.0.0.1:{port}/backend-api/codex"'
    first_table = next((i for i, line in enumerate(lines) if TABLE.match(line)), len(lines))
    lines.insert(first_table, base)
    feature_lines = [f'{key} = false' for key in FEATURE_KEYS]
    header = next(i for i, line in enumerate(lines) if FEATURES_HEADER.match(line))
    lines[header + 1:header + 1] = feature_lines
    return lines


def check_meaning(old_text, new_text, action, port):
    """行単位の編集の結果を TOML として読み直し、意図した変更だけが起きたかを確かめる。
    複数行の文字列や引用したキーなど、行単位では見分けられない書き方への誤った編集を書き込まないため。
    問題があれば理由を返す。"""
    try:
        import tomllib
    except ImportError:   # Python 3.10 以前。外すだけなら意味は変わらないので確かめずに進める
        return None if action == 'remove' else 'Python 3.11 以降が必要なため、設定を書き換えられません。'
    try:
        old = tomllib.loads(old_text)
    except tomllib.TOMLDecodeError:
        return 'TOML として読み込めないため、設定を書き換えられません。'
    try:
        new = tomllib.loads(new_text)
    except tomllib.TOMLDecodeError:
        return '書き換えると TOML として読み込めなくなるため、設定を変更できません。'
    expected = copy.deepcopy(old)
    features = expected.get('features', {})
    if not isinstance(features, dict):
        return 'features が表ではないため、設定を書き換えられません。'
    if action == 'apply':
        expected[BASE_KEY] = f'http://127.0.0.1:{port}/backend-api/codex'
        expected['features'] = dict(features, **{key: False for key in FEATURE_KEYS})
    else:
        expected.pop(BASE_KEY, None)
        for key in FEATURE_KEYS:
            features.pop(key, None)
    for data in (expected, new):
        if data.get('features') == {}:
            del data['features']   # 見出しだけ残った [features] は、表が無いのと同じに扱う
    return None if new == expected else 'ほかの設定まで変わるため、設定を書き換えられません。'


def edit(text, action, port):
    """(書き換えた内容, 書き換えない理由) を返す。"""
    newline = '\r\n' if '\r\n' in text else '\n'
    trailing = text.endswith(('\n', '\r\n')) or not text
    lines = text.splitlines()
    new_lines = apply_lines(lines, port) if action == 'apply' else remove_lines(lines)
    new_text = newline.join(new_lines) + (newline if trailing else '')
    if new_text == text:
        return text, None
    return new_text, check_meaning(text, new_text, action, port)


def smudge():
    raw = sys.stdin.buffer.read()
    out = raw
    try:
        base = os.environ.get('XDG_STATE_HOME') or str(Path.home() / '.local' / 'state')
        state = json.loads((Path(base) / 'output-gate' / 'codex.json').read_text(encoding='utf-8'))
        port = int(state.get('port') or 0)
        if state.get('enabled') and port > 0:
            new_text, reason = edit(raw.decode('utf-8'), 'apply', port)
            if reason is None:
                out = new_text.encode('utf-8')
    except Exception:  # 状態ファイルが無い・読めないなど。Git の書き出しを止めないため、入力をそのまま出す
        out = raw
    sys.stdout.buffer.write(out)


def main():
    if sys.argv[1:] == ['smudge']:
        smudge()
        return 0
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('apply', 'remove'))
    parser.add_argument('--port', type=int)
    parser.add_argument('path')
    args = parser.parse_args()
    if args.action == 'apply' and not args.port:
        parser.error('apply needs --port')
    path = Path(args.path)
    raw = path.read_bytes() if path.exists() else b''
    text = raw.decode('utf-8')
    new_text, reason = edit(text, args.action, args.port)
    if reason:
        print(f'{path}: {reason}', file=sys.stderr)
        return 1
    if new_text == text:
        print('unchanged', end='')
        return 0
    tmp = path.with_name(f'.{path.name}.output-gate.{os.getpid()}.tmp')
    tmp.write_bytes(new_text.encode('utf-8'))
    os.replace(tmp, path)
    print('changed', end='')
    return 0


if __name__ == '__main__':
    sys.exit(main())
