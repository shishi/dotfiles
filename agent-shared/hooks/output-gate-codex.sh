#!/usr/bin/env bash
# 出力ゲートの Codex 側の入口: 中継の起動、config.toml の中継の行の書き戻し、委譲の子セッションの登録。
#
#   output-gate-codex.sh session-start|prompt|stop|pre-compact|pre-model   Codex の hook (標準入力に hook の JSON)
#   output-gate-codex.sh enable [PORT] | disable                       利用者が使う切り替え
#   output-gate-codex.sh held [SESSION_ID]                             直させる前の原文の手動の回収 (24 時間まで)
#
# 差し戻し: 中継が未達の回答を案内に差し替えたターン (状態 substituted) を、Stop hook が block して同じターンで
# 直させる (blocked)。直させた後の回答にも未達が残れば中継がまた差し替えるので、そのたびに block する。
# 続けさせてよいのは、SessionStart で app-server の hooks/list により出力ゲートの Stop hook が信頼済みと確かめ、
# 続行の登録 (relay/continue/<session_id>) を書いたセッションだけ。原文が利用者に
# 届かないまま終わったターンは、同じセッションの別のターンの入力で一度だけ表示し、held でいつでも表示する。
#
# 中継を使うかとポートは、Git で追跡しないマシンごとの状態ファイル
# ($XDG_STATE_HOME/output-gate/codex.json) を正本にする。config.toml の中継の行は clean フィルターで
# Git から除いているため pull や checkout で消えることがあり、hook が状態ファイルと照合して書き戻す。
# disable は状態ファイルを先に無効にしてから行を外す。逆の順だと、次の hook が行を書き戻してしまう。
#
# 委譲の子セッション (AGENT_DELEGATED_SESSION=1) は、自分の session_id を中継の登録ディレクトリに書く。
# 中継は登録済みのセッションの出力を検査しない (親が読む機械向けの出力を書き換えないため)。
#
# SessionStart の時点で Codex は設定を読み終えている。行が無いまま始まったセッションは、行を書き戻しても
# 中継を通らず回答が検査されないため、そのセッションの入力を止めて起動し直すよう伝える。
set -u

mode=${1:-}
hook_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
bin_dir="$hook_dir/../bin"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/output-gate"
state_file="$state_root/codex.json"
relay_state="$state_root/relay"
config="${CODEX_HOME:-$HOME/.codex}/config.toml"
messages=()
stop_reason=
config_changed=false
config_failed=false

find_python() {
  local candidate
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -I -c '' >/dev/null 2>&1; then
      py_bin=$candidate
      return 0
    fi
  done
  return 1
}

json_string() {
  # ASCII だけで出す。-I では PYTHONUTF8 が効かず、Windows のパイプは ANSI コードページになるため。
  # 行末も付けない (Windows の Python が付ける CR は、$(...) で外れずに JSON の後ろに残る)。
  # 文字列は標準入力で渡す。回収する原文はコマンド行の上限 (Windows は 32,767 文字) を超えることがあるため。
  printf '%s' "$1" | "$py_bin" -I -c 'import json, sys; print(json.dumps(sys.stdin.buffer.read().decode("utf-8")), end="")'
}

finish() {
  local joined system= printed=0
  if [ "${#messages[@]}" -gt 0 ] && [ -n "${py_bin:-}" ]; then
    joined=$(printf '%s ' "${messages[@]}")
    system=$(json_string "[出力ゲート] ${joined% }")
  fi
  if [ -n "$stop_reason" ]; then
    printf '{"continue": false, "stopReason": %s%s}\n' "$(json_string "[出力ゲート] $stop_reason")" \
      "${system:+, \"systemMessage\": $system}" && printed=1
  elif [ -n "$system" ]; then
    printf '{"systemMessage":%s}\n' "$system" && printed=1
  fi
  # 回収した原文は、出力できてから表示済みの印を付ける (出せなかったら次の入力で表示し直す)。
  if [ "$printed" = 1 ] && [ -n "$system" ] && [ -n "${mark_after:-}" ]; then
    gate_state mark "$relay_state/gate/$sid" "$turn" >/dev/null
  fi
  exit 0
}

UNROUTED_REASON="このセッションは Codex の設定に中継の行が無い状態で始まったため、回答を検査できない。行は書き戻したので、Codex を起動し直して。"
ENABLE_NOTE="Codex の /hooks で出力ゲートの Stop・SessionStart・UserPromptSubmit・PreCompact・PreModelRequest hook を信頼して。信頼されていないと、中継の再起動や未達の回答の差し戻しができない。hooks.json を更新した後も信頼し直して。"
HELD_NOTE="直させる前の原文は 24 時間まで保存し、同じセッションの次の入力で一度だけ表示する。次の入力が無い単発の codex exec では bash ~/.agent-shared/hooks/output-gate-codex.sh held [session_id] で表示できる (session_id は codex exec --json が出す thread_id)。"
UNWRITABLE_REASON="Codex の設定に中継の行を書けないため、このセッションの回答を検査できない。設定を直すか、bash ~/.agent-shared/hooks/output-gate-codex.sh disable で出力ゲートを外してから起動し直して。"


default_port() {
  # Windows と WSL で別のポートにし、登録ファイルや中継の記録がそれぞれの OS の側にそろうようにする。
  if grep -qi microsoft /proc/version 2>/dev/null; then echo 18766; else echo 18765; fi
}

# 状態ファイルを読む: "enabled port" を出力する。無ければ "false 0"。
# 行末を付けずに出す (Windows の Python は行末に CR を付け、read がポートの値に含めてしまう)。
read_state() {
  "$py_bin" -I - "$state_file" <<'EOF'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding='utf-8'))
    print('true' if data.get('enabled') else 'false', int(data.get('port') or 0), end='')
except (OSError, ValueError, TypeError):
    print('false 0', end='')
EOF
}

write_state() {
  mkdir -p "$state_root" || return 1
  printf '{"enabled": %s, "port": %s}\n' "$1" "$2" >"$state_file.tmp" && mv -f "$state_file.tmp" "$state_file"
}

# hook の入力から "session_id source turn_id" を出力する。使えない値は "-" にする。
hook_fields() {
  "$py_bin" -I -c '
import json, re, sys
try:
    data = json.loads(sys.stdin.buffer.read().decode("utf-8"))
except ValueError:
    data = {}
sid = data.get("session_id") if isinstance(data, dict) else None
source = data.get("source") if isinstance(data, dict) else None
turn = data.get("turn_id") if isinstance(data, dict) else None
ok = lambda v: isinstance(v, str) and re.fullmatch(r"[A-Za-z0-9._-]{1,128}", v) and v not in (".", "..")
# 行末を付けずに出す (Windows の Python は行末に CR を付け、read が値に含めてしまう)。
print(sid if ok(sid) else "-", source if ok(source) else "-", turn if ok(turn) else "-", end="")'
}

# 中継を直せない問題は、同じセッションには一度だけ伝える。Codex は直せないまま要求を再試行し、
# 利用者の入力のたびに同じ表示を重ねても新しく分かることが無いため。中継が答えたら印を消す。
report_once() {
  local mark="$relay_state/reported/$sid"
  if [ -n "$sid" ]; then
    [ -f "$mark" ] && [ "$(cat "$mark")" = "$1" ] && return 0
    mkdir -p "$relay_state/reported" && printf '%s' "$1" >"$mark"
  fi
  messages+=("$1")
}

ensure_relay() {
  local port=$1
  mkdir -p "$relay_state" || { messages+=("中継の状態ディレクトリを作れない ($relay_state)。"); return 1; }
  local result state
  result=$("$py_bin" -I "$bin_dir/output-gate-relay.py" --port "$port" --state-dir "$relay_state" --ensure 2>/dev/null)
  state=$(printf '%s' "$result" | "$py_bin" -I -c 'import json, sys
try:
    print(json.load(sys.stdin).get("state", ""))
except ValueError:
    print("")')
  [ -n "$state" ] && [ "$state" != failed ] && [ -n "$sid" ] && rm -f -- "$relay_state/reported/$sid"
  case "$state" in
    running|started|updated) return 0 ;;
    update-deferred)
      # モデルへの要求ごとに動く hook では繰り返さず、セッションの開始と利用者の入力のときだけ伝える。
      [ "${2:-}" = quiet ] || messages+=("中継の新しい版は、処理中の要求が終わってから入れ替える。それまで古い版で動かしている。")
      return 0 ;;
    update-failed)
      messages+=("中継の新しい版に入れ替えられなかったため、古い版のまま動かしている。")
      return 0 ;;
  esac
  report_once "中継を 127.0.0.1:$port で起動できない。ほかのプロセスがポートを使っている可能性がある。直すまで Codex はモデルに接続できない。中継を外すには: bash ~/.agent-shared/hooks/output-gate-codex.sh disable"
  return 1
}

reconcile() {
  local result
  if [ "$1" = apply ]; then
    result=$("$py_bin" -I "$bin_dir/output-gate-codex-config.py" apply --port "$2" "$config" 2>/dev/null) ||
      { config_failed=true; messages+=("$config に中継の行を書けない。出力ゲートは無効のまま。"); return 1; }
    [ "$result" = changed ] && { config_changed=true; messages+=("Codex の設定に中継の行を書き戻した。"); }
  else
    result=$("$py_bin" -I "$bin_dir/output-gate-codex-config.py" remove "$config" 2>/dev/null) ||
      { messages+=("$config から中継の行を外せない。"); return 1; }
  fi
  return 0
}

# 状態を 1 か所で書き換える: 差し戻しの状態ファイルを読み、phase を変えて一時ファイルから置き換える。
#   stop FILE        substituted なら blocked にして直させた回数 (round) を 1 つ増やし、Stop hook の block を
#                    ASCII の JSON で出す
#   recover DIR TID  別のターン (TID 以外) の回収の対象で shown の無いものを表示用に出す (状態は変えない)
#   mark DIR TID     recover と同じ対象に shown を付ける (表示を出力できた後に呼ぶ)
#   held DIR...      回収の対象を shown に関係なく出す (状態は変えない)
gate_state() {
  "$py_bin" -I - "$@" <<'EOF'
import json, os, sys
from pathlib import Path

def load(path):
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None

def save(path, data):
    tmp = path.with_name(f'.{path.name}.{os.getpid()}.tmp')
    tmp.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
    os.replace(tmp, path)

def recoverable(state):
    # 原文が利用者に届いていないターン (substituted・blocked)。resolved にするとき中継が original を消す。
    return isinstance(state.get('original'), str) and state.get('phase') in ('substituted', 'blocked')

def shown(session, turn, state):
    # 利用者に見せるのは、置き換え済みの本文と検査処理の未達の文 (display)。モデルへ戻す原文 (original) は
    # 応答の規則の置き換えの前なので見せない。
    body = state.get('display') if isinstance(state.get('display'), str) else state['original']
    return (f'[出力ゲート] セッション {session} のターン {turn} の回答は、直させる前の回答のまま利用者に届いていません。\n'
            f'--- 直させる前の回答 ---\n{body}')

def targets(directory, turn):
    for path in sorted(Path(directory).glob('*.json')):
        state = load(path)
        if path.stem != turn and state and recoverable(state) and not state.get('shown'):
            yield path, state

mode = sys.argv[1]
if mode == 'stop':
    path = Path(sys.argv[2])
    state = load(path)
    if state and state.get('phase') == 'substituted' and isinstance(state.get('agent_message'), str):
        state['phase'] = 'blocked'
        state['round'] = (state.get('round') or 0) + 1
        try:
            save(path, state)
        except OSError:
            sys.exit(0)   # 書けなければ block しない (次の入力か held で原文を回収する)
        print(json.dumps({'decision': 'block', 'reason': state['agent_message']}), end='')
elif mode == 'recover':
    texts = [shown(path.parent.name, path.stem, state) for path, state in targets(sys.argv[2], sys.argv[3])]
    sys.stdout.buffer.write('\n\n'.join(texts).encode('utf-8'))
elif mode == 'mark':
    for path, state in list(targets(sys.argv[2], sys.argv[3])):
        try:
            save(path, dict(state, shown=True))
        except OSError:
            pass   # 印を付けられなければ、次の入力でもう一度表示する
else:
    texts = []
    for directory in sys.argv[2:]:
        for path in sorted(Path(directory).glob('*.json')):
            state = load(path)
            if state and recoverable(state):
                texts.append(shown(path.parent.name, path.stem, state))
    sys.stdout.buffer.write('\n\n'.join(texts).encode('utf-8'))
EOF
}

# Stop hook: 中継が案内に差し替えたターン (substituted) を block して作業を続けさせる。差し替えごとに 1 回 block し、
# 同じ差し替えを 2 回 block しない (blocked のままなら何もしない)。
# stop_hook_active では決めない (同じターンで別の Stop hook が先に block しても、出力ゲートの差し戻しはまだのため)。
# 無効のマシンと、そのターンの状態ファイルが無いときは Python を起動せずに終える。
if [ "$mode" = stop ]; then
  grep -q '"enabled": *true' "$state_file" 2>/dev/null || exit 0
  [ -d "$relay_state/gate" ] || exit 0
  input=$(cat)
  [[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9._-]{1,128})\" ]] || exit 0
  sid=${BASH_REMATCH[1]}
  [[ $input =~ \"turn_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9._-]{1,128})\" ]] || exit 0
  turn=${BASH_REMATCH[1]}
  case "$sid$turn" in *..*) exit 0 ;; esac
  [ -f "$relay_state/gate/$sid/$turn.json" ] || exit 0
  find_python || exit 0
  gate_state stop "$relay_state/gate/$sid/$turn.json"
  exit 0
fi

find_python || { case "$mode" in enable|disable|held) echo 'output-gate-codex.sh: Python が見つからない。' >&2; exit 1 ;; esac; exit 0; }
read -r enabled port < <(read_state)

sid=
turn=
hook_input=
case "$mode" in
  session-start|prompt|pre-compact)
    hook_input=$(cat)
    read -r sid source turn < <(printf '%s' "$hook_input" | hook_fields)
    [ "$sid" = - ] && sid=
    [ "$turn" = - ] && turn=
    ;;
esac

# app-server の hooks/list で、このセッションで有効な出力ゲートの Stop hook が信頼済みかを確かめる。
# 信頼済みなら 0。確かめられない・未信頼なら 1。Codex は信頼済みの hook だけを動かすため、これが通った
# セッションだけ中継に案内への差し替えを許す (続行の登録)。
stop_hook_trusted() {
  printf '%s' "$hook_input" | "$py_bin" -I -c '
import importlib.util, json, os, queue, shutil, subprocess, sys, threading, time
try:
    cwd = json.loads(sys.stdin.buffer.read().decode("utf-8")).get("cwd")
except (ValueError, AttributeError):
    cwd = None
codex = shutil.which("codex")
if not codex:
    sys.exit(1)
# app-server の停止は中継と同じ kill_tree で、子孫ごと止める (Windows の codex の shim は孫を起動するため)。
spec = importlib.util.spec_from_file_location("output_gate_relay", sys.argv[1])
relay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(relay)
proc = subprocess.Popen([codex, "app-server"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, start_new_session=os.name != "nt")
deadline = time.monotonic() + 8
lines = queue.Queue()
threading.Thread(target=lambda: [lines.put(line) for line in iter(proc.stdout.readline, b"")] and None,
                 daemon=True).start()
def send(message):
    proc.stdin.write((json.dumps(message) + "\n").encode())
    proc.stdin.flush()
def answer(request_id):
    while True:
        try:
            line = lines.get(timeout=max(0.01, deadline - time.monotonic()))
        except queue.Empty:
            return None
        message = json.loads(line)
        if isinstance(message, dict) and message.get("id") == request_id and "method" not in message:
            return message.get("result")
trusted = False
try:
    send({"id": 1, "method": "initialize", "params": {"clientInfo": {"name": "output-gate", "version": "1"},
                                                      "capabilities": {"experimentalApi": True}}})
    if answer(1) is not None:
        send({"method": "initialized", "params": {}})
        send({"id": 2, "method": "hooks/list", "params": {"cwds": [cwd] if isinstance(cwd, str) else []}})
        result = answer(2) or {}
        hooks = [h for entry in result.get("data") or [] for h in entry.get("hooks") or []]
        gate = [h for h in hooks if h.get("eventName") == "stop" and h.get("enabled") is not False
                and "output-gate-codex.sh stop" in (h.get("command") or "")]
        trusted = bool(gate) and all(h.get("trustStatus") == "trusted" for h in gate)
except (OSError, ValueError, AttributeError):
    trusted = False
finally:
    relay.kill_tree(proc)
sys.exit(0 if trusted else 1)' "$bin_dir/output-gate-relay.py"
}

case "$mode" in
  session-start)
    if [ "${AGENT_DELEGATED_SESSION:-}" = 1 ] && [ -n "$sid" ]; then
      mkdir -p "$relay_state/delegated" && : >"$relay_state/delegated/$sid"
    fi
    if [ "$enabled" = true ]; then
      ensure_relay "$port"
      reconcile apply "$port"
      # 設定を読み込んで始まるスレッド (startup・resume・clear・fork) を止める。compact だけは同じスレッドの
      # 中で続き、始めたときの設定のまま中継を通っている。委譲の子は意図して中継を通さない (起動行で
      # openai_base_url を空にする) ので止めない。
      if [ "${AGENT_DELEGATED_SESSION:-}" != 1 ] && [ -n "$sid" ] && [ "$source" != compact ]; then
        if [ "$config_failed" = true ]; then
          stop_reason=$UNWRITABLE_REASON
        elif [ "$config_changed" = true ]; then
          stop_reason=$UNROUTED_REASON
        fi
        [ -n "$stop_reason" ] && mkdir -p "$relay_state/unrouted" && printf '%s' "$stop_reason" >"$relay_state/unrouted/$sid"
      fi
      # 続行の登録: このセッションで出力ゲートの Stop hook が動く (信頼済み) と確かめられたときだけ書く。
      # 登録の無いセッションでは、中継は未達の回答を案内に差し替えず、未達の項目を添えた原文を流す。
      # 起動し直しを求めるセッションは中継を通らないので確かめない (hook の時間制限に収めるため)。compact は
      # 同じスレッドの中で続くので、開始時の登録をそのまま使う。
      if [ "${AGENT_DELEGATED_SESSION:-}" != 1 ] && [ -n "$sid" ] && [ "$source" != compact ]; then
        if [ -z "$stop_reason" ] && stop_hook_trusted; then
          mkdir -p "$relay_state/continue" && : >"$relay_state/continue/$sid"
        else
          rm -f -- "$relay_state/continue/$sid"
        fi
      fi
    fi
    finish
    ;;
  prompt)
    if [ "$enabled" = true ]; then
      ensure_relay "$port"
      reconcile apply "$port"
    fi
    [ -n "$sid" ] && [ -s "$relay_state/unrouted/$sid" ] && stop_reason=$(cat "$relay_state/unrouted/$sid")
    # 前のターンで直させる前の原文が利用者に届かないまま終わっていれば (Stop hook が動かなかった、直させている
    # 途中で中断した)、別のターンの入力が来たこのときに一度だけ表示する。状態は消さない (24 時間の掃除と held に任せる)。
    if [ -n "$sid" ] && [ -n "$turn" ] && [ -d "$relay_state/gate/$sid" ]; then
      recovered=$(gate_state recover "$relay_state/gate/$sid" "$turn")
      [ -n "$recovered" ] && messages+=("$recovered") && mark_after=1
    fi
    finish
    ;;
  held)
    # 手動の回収: 直させる前の原文と未達の項目を、表示済みかに関係なくセッションとターンごとに出す。
    if [ -n "${2:-}" ]; then
      case "$2" in *[!A-Za-z0-9._-]*|.|..) echo "output-gate-codex.sh: session_id の形が違う。" >&2; exit 2 ;; esac
      dirs=("$relay_state/gate/$2")
    else
      dirs=("$relay_state"/gate/*)
    fi
    text=$(gate_state held "${dirs[@]}")
    printf '%s\n' "${text:-回収できる原文は無い。}" "$HELD_NOTE"
    ;;
  pre-compact)
    # 利用者の入力から始まらない要求 (compaction) の前にも、止まった中継を起動し直す。
    [ "$enabled" = true ] && ensure_relay "$port" quiet
    finish
    ;;
  pre-model)
    # ターンの途中で止まった中継を起動し直す。codex/hooks.json で async にしてあるため、Codex は要求を
    # この hook の終わりまで待たない。中継がまだ答えなければ、その要求は Codex の再試行で吸収する。
    # Codex は PreModelRequest の hook の標準出力を読まないため、何も出さない。
    [ "$enabled" = true ] && ensure_relay "$port" quiet
    exit 0
    ;;
  enable)
    previous_port=$port
    state_existed=false
    [ -e "$state_file" ] && state_existed=true
    port=${2:-$(default_port)}
    if ! ensure_relay "$port"; then
      printf '%s\n' "${messages[@]}" >&2
      exit 1
    fi
    write_state true "$port" || { echo "$state_file を書けない。" >&2; exit 1; }
    if ! reconcile apply "$port"; then
      if [ "$state_existed" = true ]; then
        write_state "$enabled" "$previous_port" || echo "$state_file を復元できない。" >&2
      else
        rm -f -- "$state_file" || echo "$state_file を削除できない。" >&2
      fi
      printf '%s\n' "${messages[@]}" >&2
      exit 1
    fi
    printf '%s\n' "${messages[@]:-出力ゲートを有効にした (127.0.0.1:$port)。}" "$ENABLE_NOTE" "$HELD_NOTE"
    ;;
  disable)
    write_state false "${port:-0}" || { echo "$state_file を書けない。" >&2; exit 1; }
    if [ -e "$config" ] || [ -L "$config" ]; then
      reconcile remove
    fi
    printf '%s\n' "${messages[@]:-出力ゲートを無効にした。Codex を起動し直すと中継を通らない。}"
    ;;
  *)
    echo "usage: output-gate-codex.sh session-start|prompt|stop|pre-compact|pre-model|enable [PORT]|disable|held [SESSION_ID]" >&2
    exit 2
    ;;
esac
