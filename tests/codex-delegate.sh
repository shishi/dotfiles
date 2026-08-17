#!/usr/bin/env bash
# codex-delegate skill の静的検査。
# 使い方: bash tests/codex-delegate.sh
#
# codex を起動しない。実行を伴う検証(sandbox が効くか・記憶が書かれないか・
# timeout 後の停止が届くか等)は spec の「検証」節が担い、OpenAI 側の利用枠を要する。
# ここで見るのは、リポジトリ内のファイルだけで判定できることに限る。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$REPO/claude/skills/codex-delegate"
SKILL="$SKILL_DIR/SKILL.md"
SCHEMA="$SKILL_DIR/schema.json"
SETTINGS="$REPO/claude/settings.json"
CLAUDE_MD="$REPO/claude/CLAUDE.md"
INSTALLER="$REPO/claude/install-plugins.sh"
FAILURES=0

pass() { echo "  ok: $1"; }
fail() { echo "  NG: $1"; FAILURES=$((FAILURES + 1)); }

check() { # check <desc> <cmd...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

check_not() { # 成功したら NG
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$desc"; else pass "$desc"; fi
}

command -v jq >/dev/null 2>&1 || { echo "codex-delegate: jq not found; cannot run"; exit 2; }

echo "# schema.json (出力契約)"

check "存在する" test -f "$SCHEMA"
check "valid JSON" jq -e . "$SCHEMA"
check "additionalProperties が false" \
  jq -e '.additionalProperties == false' "$SCHEMA"
check "type が object" jq -e '.type == "object"' "$SCHEMA"
# 構造化出力は全キーの明示を要求するため、properties と required は同一集合でなければならない
check "properties と required が同一集合" \
  jq -e '(.properties | keys | sort) == (.required | sort)' "$SCHEMA"
check "required が 6 プロパティ" jq -e '(.required | length) == 6' "$SCHEMA"
check "status の enum が done/partial/blocked" \
  jq -e '.properties.status.enum == ["done","partial","blocked"]' "$SCHEMA"
# maxLength / maxItems だけが実効の上限。description に書いた長さの指示は注釈であり
# 適合検査の対象にならないため、上限として数えない
check "summary に maxLength" jq -e '.properties.summary.maxLength > 0' "$SCHEMA"
for arr in changed_files findings next_steps blockers; do
  check "$arr に maxItems" jq -e --arg a "$arr" '.properties[$a].maxItems > 0' "$SCHEMA"
  check "$arr の items に maxLength" \
    jq -e --arg a "$arr" '.properties[$a].items.maxLength > 0' "$SCHEMA"
done
# 上限の合計 = 1 回の委譲が Claude の context へ加えうる最大量。SKILL.md と plan が
# 22,600 文字と書いているので、schema 側を緩めたらここで落ちる
check "上限の合計が 22,600 文字を超えない" jq -e '
  (.properties.summary.maxLength)
  + (.properties.changed_files.maxItems * .properties.changed_files.items.maxLength)
  + (.properties.findings.maxItems     * .properties.findings.items.maxLength)
  + (.properties.next_steps.maxItems   * .properties.next_steps.items.maxLength)
  + (.properties.blockers.maxItems     * .properties.blockers.items.maxLength)
  <= 22600' "$SCHEMA"

echo
echo "# SKILL.md (手順)"

check "存在する" test -f "$SKILL"
check "frontmatter に name: codex-delegate" \
  grep -q '^name: codex-delegate$' "$SKILL"
check "frontmatter に description" grep -q '^description:' "$SKILL"

# 実行スニペットを抽出する。```sh のブロックだけが実行対象で、プロンプトへ入れる
# 文面は ```text に置くため巻き込まれない。
# 引数なしの mktemp は Claude Code の Bash sandbox 内で Operation not permitted に
# なるため、テンプレートを ${TMPDIR:-/tmp} 配下で明示する
SNIP="$(mktemp "${TMPDIR:-/tmp}/codex-delegate-snippet-XXXXXX")"
awk '/^```sh$/{f=1;next} /^```$/{f=0} f' "$SKILL" > "$SNIP"
check "sh ブロックが存在する" test -s "$SNIP"
# 実行系は zsh 5.9.2。bash -n は別言語を検査するので使わない。POSIX sh の範囲に
# 収まっていることも見る
check "zsh -n を通る" zsh -n "$SNIP"
check "sh -n を通る"  sh  -n "$SNIP"
# heredoc をスニペットに持たせない。引用符なしのデリミタは本文中の $(...) と
# バッククォートを実行し、引用符ありでも本文にデリミタと同一の行があればそこで
# 終わって残りがコマンドになる。どちらも構文としては正しいので -n では捕まらない
check_not "スニペットに heredoc が無い" grep -q '<<' "$SNIP"
check_not "bypass フラグを使っていない" grep -q 'dangerously-bypass' "$SNIP"

# -s は必ず指定する。config.toml の sandbox_mode は workspace-write なので、
# 指定を落とすと explore でも書き込みできる状態で走る
check "codex exec に -s がある" grep -q 'codex exec -s' "$SNIP"
# 6 つの --config を毎回渡す。-s が上書きするのは sandbox_mode だけで、書き込み
# ルート・ネットワーク到達性・承認方針・記憶機能は config 側に残る
for key in approval_policy=never features.memories=false \
           memories.generate_memories=false memories.use_memories=false \
           sandbox_workspace_write.network_access=false \
           'sandbox_workspace_write.writable_roots=\[\]'; do
  check "--config $key がある" grep -q -- "--config .*$key" "$SNIP"
done
check "--config がちょうど 6 個" \
  test "$(grep -c -- '--config' "$SNIP")" -eq 6

# 出力経路: 最終メッセージは -o のファイルへ、進捗出力は run.log へ。
# リダイレクトを落とすと codex の進捗出力全文が context に入り、削減の目的が失われる
check "最終メッセージを out.json へ落とす" grep -q -- '-o "$WORK/out.json"' "$SNIP"
check "stdout/stderr を run.log へ逃がす" grep -q '> "\$WORK/run.log" 2>&1' "$SNIP"
# 失敗時のログはバイトで区切る。行数では 1 行が JSON や stack trace になる codex の
# ログで上限にならない
check "失敗時のログをバイトで区切る" grep -q 'tail -c 4000' "$SNIP"

# 順序: gitleaks は codex より前。trap は gitleaks より後(手前の中断では
# プロンプトを残し、直して再委譲できるようにする)
check "gitleaks が codex exec より前" test \
  "$(grep -n 'gitleaks' "$SNIP" | head -1 | cut -d: -f1)" -lt \
  "$(grep -n 'codex exec' "$SNIP" | head -1 | cut -d: -f1)"
check "trap が gitleaks より後" test \
  "$(grep -n 'gitleaks' "$SNIP" | head -1 | cut -d: -f1)" -lt \
  "$(grep -n 'trap ' "$SNIP" | head -1 | cut -d: -f1)"
check "trap が codex exec より前" test \
  "$(grep -n 'trap ' "$SNIP" | head -1 | cut -d: -f1)" -lt \
  "$(grep -n 'codex exec' "$SNIP" | head -1 | cut -d: -f1)"
# 使用済みの目印は run.log。out.json は目印にならない(存在するのは正常終了した
# 委譲だけで、その経路では作業ディレクトリごと消えている)
check "使用済み判定が run.log を見る" \
  grep -q '\[ -e "\$WORK/run.log" \] && exit 96' "$SNIP"
# 引数なしの mktemp -d は sandbox 内で Operation not permitted になる
check "mktemp -d にテンプレートを渡す" \
  grep -q 'mktemp -d "\${TMPDIR:-/tmp}/codex-delegate-XXXXXX"' "$SNIP"

rm -f "$SNIP"

# 終了コードは障害対応中に読まれる。3 つすべてに意味と対処が書かれていること
for code in 96 97 98; do
  check "終了コード $code を説明している" grep -q "| $code |" "$SKILL"
done

echo
echo "# CLAUDE.md (判断基準)"

# 判断基準は常時 context に載る CLAUDE.md にしか置けない。skill は呼ばれてから
# 読まれるため、基準が skill 本文にあると自律発火しない
check "codex-delegate skill を参照している" grep -q 'codex-delegate' "$CLAUDE_MD"
for kind in explore chore implement; do
  check "委譲種別 $kind がある" grep -q "$kind" "$CLAUDE_MD"
done
check "委譲しない条件を書いている" grep -q '委譲しない' "$CLAUDE_MD"
# OpenAI 枠の消費は「上限・予算を示さない数値を書かない」規律の対象。委譲が
# 無料ではないことを判断基準の側に書く
check "OpenAI 枠を消費する旨を書いている" grep -q 'OpenAI' "$CLAUDE_MD"
# レビューは委譲しない。既存のゲートと責務が重ならないことを基準側で明示する
check "レビューを委譲しない旨を書いている" grep -q 'review-gate' "$CLAUDE_MD"

echo
echo "# settings.json / install-plugins.sh (配線)"

check "settings.json が valid JSON" jq -e . "$SETTINGS"
# これが無いと codex の app-server 初期化が Operation not permitted で落ちる。
# 記法は <cmd>:* — コマンド名だけだと exact マッチになり、引数付きの呼び出しには
# 無言で効かない
check "excludedCommands に codex:* がある" \
  jq -e '.sandbox.excludedCommands | index("codex:*")' "$SETTINGS"
# 無効化は false で表す。キーごと削除すると install-plugins.sh の
# 「値が true のものだけ install」という判定材料が消える
check "codex プラグインが false" \
  jq -e '.enabledPlugins["codex@openai-codex"] == false' "$SETTINGS"
check "codex プラグインのキー自体は残っている" \
  jq -e '.enabledPlugins | has("codex@openai-codex")' "$SETTINGS"
check_not "extraKnownMarketplaces から openai-codex が消えている" \
  jq -e '.extraKnownMarketplaces | has("openai-codex")' "$SETTINGS"
# codex-review skill が使うので残す。撤去のついでに落とさない
check "bypass grant は残っている" jq -e '
  .permissions.allow
  | index("Bash(codex exec --dangerously-bypass-approvals-and-sandbox:*)")' "$SETTINGS"
# install-plugins.sh 側にマッピングが残っていると、新しいマシンで再導入される
check_not "install-plugins.sh に openai-codex が無い" \
  grep -q 'openai-codex' "$INSTALLER"
# このファイルは #!/usr/bin/env bash で bash として実行される。SKILL.md の
# スニペット(実行系は zsh)とは検査すべき言語が違う
check "install-plugins.sh が bash -n を通る" bash -n "$INSTALLER"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "codex-delegate: all checks passed"
else
  echo "codex-delegate: $FAILURES check(s) failed"
fi
[ "$FAILURES" -eq 0 ]
