#!/usr/bin/env bash
# 出力ゲートの Codex 側の入口: 中継の起動、config.toml の中継の行の書き戻し、委譲の子セッションの登録。
#
#   output-gate-codex.sh session-start|prompt|pre-compact|pre-model|session-end   Codex の hook (標準入力に hook の JSON)
#   output-gate-codex.sh enable [PORT] | disable                       利用者が使う切り替え
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
  "$py_bin" -I -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"
}

finish() {
  if [ -n "$stop_reason" ]; then
    printf '{"continue": false, "stopReason": %s}\n' "$(json_string "[出力ゲート] $stop_reason")"
  elif [ "${#messages[@]}" -gt 0 ] && [ -n "${py_bin:-}" ]; then
    local joined
    joined=$(printf '%s ' "${messages[@]}")
    printf '{"systemMessage":%s}\n' "$(json_string "[出力ゲート] ${joined% }")"
  fi
  exit 0
}

UNROUTED_REASON="このセッションは Codex の設定に中継の行が無い状態で始まったため、回答を検査できない。行は書き戻したので、Codex を起動し直して。"
UNWRITABLE_REASON="Codex の設定に中継の行を書けないため、このセッションの回答を検査できない。設定を直すか、bash ~/.agent-shared/hooks/output-gate-codex.sh disable で出力ゲートを外してから起動し直して。"


default_port() {
  # Windows と WSL で別のポートにし、登録ファイルや中継の記録がそれぞれの OS の側にそろうようにする。
  if grep -qi microsoft /proc/version 2>/dev/null; then echo 18766; else echo 18765; fi
}

# 状態ファイルを読む: "enabled port" を出力する。無ければ "false 0"。
read_state() {
  "$py_bin" -I - "$state_file" <<'EOF'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding='utf-8'))
    print('true' if data.get('enabled') else 'false', int(data.get('port') or 0))
except (OSError, ValueError, TypeError):
    print('false 0')
EOF
}

write_state() {
  mkdir -p "$state_root" || return 1
  printf '{"enabled": %s, "port": %s}\n' "$1" "$2" >"$state_file.tmp" && mv -f "$state_file.tmp" "$state_file"
}

# hook の入力から "session_id source" を出力する。使えない値は "-" にする。
hook_fields() {
  "$py_bin" -I -c '
import json, re, sys
try:
    data = json.loads(sys.stdin.buffer.read().decode("utf-8"))
except ValueError:
    data = {}
sid = data.get("session_id") if isinstance(data, dict) else None
source = data.get("source") if isinstance(data, dict) else None
ok = lambda v: isinstance(v, str) and re.fullmatch(r"[A-Za-z0-9._-]{1,128}", v) and v not in (".", "..")
# 行末を付けずに出す (Windows の Python は行末に CR を付け、read が値に含めてしまう)。
print(sid if ok(sid) else "-", source if ok(source) else "-", end="")'
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
  messages+=("中継を 127.0.0.1:$port で起動できない。ほかのプロセスがポートを使っている可能性がある。直すまで Codex はモデルに接続できない。中継を外すには: bash ~/.agent-shared/hooks/output-gate-codex.sh disable")
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

find_python || { case "$mode" in enable|disable) echo 'output-gate-codex.sh: Python が見つからない。' >&2; exit 1 ;; esac; exit 0; }
read -r enabled port < <(read_state)

case "$mode" in
  session-start|session-end|prompt)
    read -r sid source < <(hook_fields)
    [ "$sid" = - ] && sid=
    ;;
esac

case "$mode" in
  session-start|session-end)
    if [ "${AGENT_DELEGATED_SESSION:-}" = 1 ] && [ -n "$sid" ]; then
      if [ "$mode" = session-start ]; then
        mkdir -p "$relay_state/delegated" && : >"$relay_state/delegated/$sid"
      else
        rm -f -- "$relay_state/delegated/$sid"
      fi
    fi
    [ "$mode" = session-end ] && [ -n "$sid" ] && rm -f -- "$relay_state/unrouted/$sid"
    if [ "$mode" = session-start ] && [ "$enabled" = true ]; then
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
    fi
    finish
    ;;
  prompt)
    if [ "$enabled" = true ]; then
      ensure_relay "$port"
      reconcile apply "$port"
    fi
    [ -n "$sid" ] && [ -s "$relay_state/unrouted/$sid" ] && stop_reason=$(cat "$relay_state/unrouted/$sid")
    finish
    ;;
  pre-compact|pre-model)
    # 利用者の入力から始まらない要求 (compaction など) の前にも、止まった中継を起動し直す。
    [ "$enabled" = true ] && ensure_relay "$port" quiet
    finish
    ;;
  enable)
    port=${2:-$(default_port)}
    write_state true "$port" || { echo "$state_file を書けない。" >&2; exit 1; }
    ensure_relay "$port"
    reconcile apply "$port"
    printf '%s\n' "${messages[@]:-出力ゲートを有効にした (127.0.0.1:$port)。}"
    ;;
  disable)
    write_state false "${port:-0}" || { echo "$state_file を書けない。" >&2; exit 1; }
    reconcile remove
    printf '%s\n' "${messages[@]:-出力ゲートを無効にした。Codex を起動し直すと中継を通らない。}"
    ;;
  *)
    echo "usage: output-gate-codex.sh session-start|prompt|pre-compact|pre-model|session-end|enable [PORT]|disable" >&2
    exit 2
    ;;
esac
