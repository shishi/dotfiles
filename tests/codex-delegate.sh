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
# maxLength / maxItems の単純和。SKILL.md が 22,600 文字と書いているので、schema 側を
# 緩めたらここで落ちる。これは受信量の上限ではない — 値をデコードしたあとの文字数の和で
# あって、バイト数・エスケープ・JSON の構造分がこれに乗る(内訳は SKILL.md にある)
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
# NUL バイトはエディタでも diff でも見えないまま入り、ファイルをテキストとして扱う
# 経路(file(1) の判定、grep のバイナリ扱い、一部の Markdown 処理)を静かに壊す。
# 制御文字を説明する本文を書くときに実物を書いてしまう事故が起きるため、機械で見る
no_nul() { [ "$(tr -d '\0' < "$1" | wc -c)" -eq "$(wc -c < "$1")" ]; }
check "SKILL.md に NUL バイトが無い" no_nul "$SKILL"
check "schema.json に NUL バイトが無い" no_nul "$SCHEMA"

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
           'sandbox_workspace_write.network_access=\$NET' \
           'sandbox_workspace_write.writable_roots=\[\]'; do
  check "--config $key がある" grep -q -- "--config .*$key" "$SNIP"
done
check "--config がちょうど 6 個" \
  test "$(grep -c -- '--config' "$SNIP")" -eq 6
# ネットワークはタスクごとの選択だが、既定は遮断でなければならない。`^NET=false` の
# 存在だけでは足りない — あとから `NET=true` が続けば最終値は true になり、開けるつもりの
# ないタスクにも開いた状態で渡る。代入がちょうど 1 件で、それが false であることを見る
check "NET への代入がちょうど 1 件" \
  test "$(grep -c '^NET=' "$SNIP")" -eq 1
check "その 1 件が NET=false" grep -q '^NET=false' "$SNIP"
# read-only では network_access が読まれないため、NET=true にしても遮断されたまま走る。
# エラーにならず素通りする組み合わせなので、手順が明示していること
check "read-only で NET が効かない旨を書いている" \
  grep -q 'read-only` では `NET=true` が黙って効かない' "$SKILL"

# 「委譲専用の検査機構は持たない」だけを読むと委譲先が無防備に走ると取れる。実際には codex 側の
# PreToolUse hook が委譲先のコマンドにも効くので、ガードの有無を前提にした判断を誤らせないこと
check "委譲先にも hook が効く旨を書いている" \
  grep -q 'codex 側の hook は委譲の中でも効く' "$SKILL"

# 出力経路: 最終メッセージは -o のファイルへ、進捗出力は run.log へ。
# リダイレクトを落とすと codex の進捗出力全文が context に入り、削減の目的が失われる
check "最終メッセージを out.json へ落とす" grep -q -- '-o "$WORK/out.json"' "$SNIP"
check "stdout/stderr を run.log へ逃がす" grep -q '> "\$WORK/run.log" 2>&1' "$SNIP"
# 失敗時のログはバイトで区切る。行数では 1 行が JSON や stack trace になる codex の
# ログで上限にならない
check "失敗時のログをバイトで区切る" grep -q 'tail -c 4000' "$SNIP"

# 順序: gitleaks < 目印取得 < trap < cp。gitleaks で止まった時点では目印を取らないので、
# 直して同じディレクトリから再委譲できる。cp が trap より後なのは、目印を取ったあとに
# cp が失敗したディレクトリを後始末の対象に入れるため
line_of() { # line_of <パターン> — 見つからなければ 0
  grep -n -- "$1" "$SNIP" | head -1 | cut -d: -f1
}
check_order() { # check_order <desc> <先に来るパターン> <後に来るパターン>
  # 両方が実在することを要求する。片方が消えて 0 になったとき「0 < 正数」で
  # 通ってしまうと、検査そのものが消えたことをテストが見逃す
  local a b
  a="$(line_of "$2")"; b="$(line_of "$3")"
  if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then pass "$1"; else fail "$1"; fi
}
check_order "gitleaks が codex exec より前" 'gitleaks' 'codex exec'
check_order "目印取得が gitleaks より後" 'gitleaks' 'mkdir "\$WORK/run.claim"'
check_order "trap が目印取得より後" 'mkdir "\$WORK/run.claim"' 'trap '
check_order "trap が codex exec より前" 'trap ' 'codex exec'
check_order "cp が trap より後" 'trap ' 'cp "\$HOME/.claude/skills'
# パスの形を照合してから rm -rf の射程に入れる。prompt.md の有無だけでは、委譲の
# 作業ディレクトリ以外にも同名のファイルが存在しうるため射程を絞れない
# 照合は最後の要素に対して行う。パス全体を */codex-delegate-* で見る形だと末尾の * が
# / も含むため、/tmp/codex-delegate-ABCDEF/../victim のような形が通り抜ける
check "作業ディレクトリの名前の形を最後の要素で照合している" \
  grep -q 'case "\${WORK##\*/}" in (codex-delegate-??????)' "$SNIP"
check_order "形の照合が trap より前" 'case "\${WORK##\*/}" in' 'trap '
# 使用済みの目印は mkdir で原子的に取る。「存在を見てから作る」形だと、同じパスを
# 2 つの呼び出しへ貼ったときに両方が判定を通り抜ける。run.log はリダイレクトで
# 作られるので判定より後になり、out.json は正常終了した委譲にしか存在せず、その
# 経路では作業ディレクトリごと消えている
check "使用済み判定を mkdir で原子的に取る" \
  grep -q 'mkdir "\$WORK/run.claim" || exit 96' "$SNIP"
# mkdir のエラーを握り潰さない。96 は「起動済み」と「目印を作れない」を兼ねるので、
# エラー文が出ないと障害対応中に区別できない
check_not "mkdir の stderr を捨てていない" \
  grep -q 'mkdir "\$WORK/run.claim" 2>/dev/null' "$SNIP"
check_not "存在を見てから作る形の判定を残していない" \
  grep -q '\[ -e "\$WORK/run.log" \]' "$SNIP"
# 引数なしの mktemp -d は sandbox 内で Operation not permitted になる
check "mktemp -d にテンプレートを渡す" \
  grep -q 'mktemp -d "\${TMPDIR:-/tmp}/codex-delegate-XXXXXX"' "$SNIP"

rm -f "$SNIP"

# 終了コードは障害対応中に読まれる。5 つすべてに意味と対処が書かれていること。
# コード列の照合だけでは意味・対処が空の行を通すため、両列に非空白があることまで見る
for code in 0 96 97 98 143; do
  check "終了コード $code に意味と対処がある" \
    grep -qE "^\| $code \|[^|]*[^|[:space:]][^|]*\|[^|]*[^|[:space:]][^|]*\|\$" "$SKILL"
done

echo
echo "# CLAUDE.md (判断基準)"

# skill は呼ばれてから読まれるので、CLAUDE.md が skill の名前を持っていなければ
# 自律発火の経路が無い。ここで見るのはその配線 1 点だけ — 判断基準の内容が妥当かは
# 本文に語が含まれるかでは測れず、grep はレビューの代わりにならない
check "codex-delegate skill を参照している" grep -q 'codex-delegate' "$CLAUDE_MD"

echo
echo "# settings.json / install-plugins.sh (配線)"

check "settings.json が valid JSON" jq -e . "$SETTINGS"
# これが無いと codex の app-server 初期化が Operation not permitted で落ちる。
# 記法は <cmd>:* — コマンド名だけだと exact マッチになり、引数付きの呼び出しには
# 無言で効かない
check "excludedCommands に codex:* がある" \
  jq -e '.sandbox.excludedCommands | index("codex:*")' "$SETTINGS"
# プラグインは無効化ではなく撤去する。追跡ファイルのどこからも参照が消えていること —
# enabledPlugins に残っていると install-plugins.sh が値を見て判断する対象になり、
# extraKnownMarketplaces に残っていると新しいマシンで marketplace が登録される。
# `claude plugin uninstall` は enabledPlugins のキー自体を落とすので、キーを false で
# 残す形は CLI の実際の振る舞いと衝突する
check_not "enabledPlugins から codex が消えている" \
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
