# 委譲された子のセッションかを判定する。kata-entry.sh・kata-first.sh・kata-completion.sh が読み込む。
#   delegated_session <hook の入力の session_id>
# 委譲された子には利用者がおらず、設計・作業場所・統合は司令塔が担うため、hook は司令塔向けの案内と関門を外す。

# 子は AGENT_DELEGATED_SESSION=1 で示す。T3 Code の delegate_task が起動した子にはこの変数が付かないため、
# T3 がその子のスレッドに付ける ID の接頭辞でも見分ける。T3 はこの ID を Claude Code にはプロセスの環境で渡すが、
# Codex にはシェルコマンドの環境 (shell_environment_policy) でしか渡さず hook には届かないため、T3 の記録も引く。
delegated_session() {
  [ "${AGENT_DELEGATED_SESSION:-}" = 1 ] && return 0
  case ${T3CODE_THREAD_ID:-} in thread:delegated-task:*) return 0 ;; esac
  t3_delegated_session "${1:-}"
}

# T3 の状態 DB で、この会話が属する T3 のスレッドが delegate_task の子かを引く。Codex の hook の session_id は
# Codex のスレッド ID で、T3 は会話ごとの行の payload_json.nativeThreadRef.nativeId にこの ID を記録する
# (T3 自身もこの列で会話の属するスレッドを引いている)。T3 0.1.11 の内部の表と JSON の形に依存するため、
# T3 の版が変わったら表名と列を確かめ直す。T3 は保存先を T3CODE_HOME (既定は ~/.t3) で決めるが、
# --base-dir で起動したときの保存先はここから分からない。
# T3 の外で同じ会話を codex resume しても session_id は同じなので、T3 が起動した Codex の本体に付く
# CODEX_INTERNAL_ORIGINATOR_OVERRIDE (T3 0.1.11 では "T3 Code") があるときだけ引く。T3 自身の持ち主の照会
# (AcpRegistrySessions.findOwner) に合わせて Codex の行と削除されていないスレッドに絞り、対応するスレッドが
# 一つに決まらないときも子と判定しない。
# DB が無い・読めない・形が変わったときは子と判定せず、hook は通常の処理を続ける。T3 の稼働を妨げないよう
# 読み取り専用で開き、ロック中はビジー待ちせずに失敗させる (sqlite3 の既定)。~/.sqliterc は出力の形を
# 変えうるため読まない。
t3_delegated_session() {
  [ "${CODEX_INTERNAL_ORIGINATOR_OVERRIDE:-}" = "T3 Code" ] || return 1
  case $1 in '' | *[!A-Za-z0-9._-]*) return 1 ;; esac
  local db=${T3CODE_HOME:-$HOME/.t3}/userdata/statev2.sqlite
  [ -f "$db" ] || return 1
  [ "$(sqlite3 -init /dev/null -batch -readonly "$db" \
    "SELECT COUNT(DISTINCT provider.thread_id) = 1 AND MIN(provider.thread_id) GLOB 'thread:delegated-task:*'
     FROM orchestration_v2_projection_provider_threads AS provider
     JOIN orchestration_v2_projection_threads AS thread ON thread.thread_id = provider.thread_id
     WHERE provider.driver = 'codex'
       AND json_extract(provider.payload_json, '\$.nativeThreadRef.nativeId') = '$1'
       AND thread.deleted_at IS NULL" \
    < /dev/null 2> /dev/null)" = 1 ]
}
