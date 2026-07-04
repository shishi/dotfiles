# パーソナル永続記憶システム設計

日付: 2026-07-05
状態: レビュー待ち

## 目的

Claude Code のセッションをまたいで持続する個人記憶(ユーザーの好み・確定方針・プロジェクト固有の知見)を、git 管理・マシン間同期可能な形で持つ。ビルトインのプロジェクト記憶(`~/.claude/projects/<slug>/memory/`)は `claude/projects/` が git 非追跡のため履歴も同期もなく、また dotfiles リポジトリは **public** のため個人情報を含む記憶を置けない。この2つの制約を同時に解決する。

## 全体構成

```
[private repo: claude-memory]        ← 記憶本体。GitHub プライベートリポジトリ
    MEMORY.md                        ← グローバル索引(1記憶 = 1行フック)
    <topic>.md                       ← グローバル記憶(1ファイル1トピック)
    projects/<slug>.md               ← プロジェクト別記憶(1プロジェクト1ファイル)

[public repo: dotfiles]              ← 仕組みだけ。秘密情報ゼロ
    claude/memory  → symlink → claude-memory のクローン先
    claude/hooks/inject-memory.sh    ← SessionStart hook スクリプト
    claude/settings.json             ← hook 登録
    claude/CLAUDE.md                 ← 書き込みルール追記
    claude/skills/memory-consolidate/SKILL.md  ← 整理(consolidation)skill
    setup.sh                         ← clone + symlink 手順追記
```

- `<slug>` はプロジェクトの同一性を表す ID。マシン・チェックアウトパスに依存させないため、次の優先順で決める:
  1. **remote URL**: cwd が git リポジトリで `origin` があれば、URL を `ホスト/オーナー/リポジトリ` に正規化して slug 化(`git@github.com:shishi/dotfiles.git` / `https://github.com/shishi/dotfiles` → いずれも `github.com-shishi-dotfiles`)。ssh/https の差・`.git` 有無を吸収し、worktree も同一プロジェクト扱いになる。
  2. **ghq root 相対パス**: remote が無い場合、cwd が ghq root(`ghq root` → 無ければ `git config ghq.root` → 既定 `~/ghq`。`~` は展開)配下なら、root からの相対パスを slug 化(`<root>/github.com/shishi/foo` → `github.com-shishi-foo`)。ghq の配置規約は remote URL のミラーなので、**push 前でも将来の remote slug と一致**し、push 後に記憶が分裂しない。
  3. **path-slug**: いずれでもなければ cwd フルパスの `:` `\` `/` を `-` に置換(例: `C--Users-shishi-dev-foo`)。
- 既知の分裂ケース: ghq root 外で始めたプロジェクトを後から remote に push すると path-slug → remote slug に変わる。その時点で `projects/` 内のファイルを手動リネームして引き継ぐ(稀な一回きりの操作なので自動化しない)。
- symlink `claude/memory` は dotfiles の `.gitignore`(`/claude/*` デフォルト無視)により**追跡されない**。ホワイトリストに追加しないこと。
- クローン先の既定は `~/dev/claude-memory`(環境変数 `CLAUDE_MEMORY_DIR` で上書き可。hook・setup.sh は symlink 経由の固定パス `~/.claude/memory` だけを見る)。

## コンポーネント

### 1. 記憶ファイル形式

```markdown
---
name: <kebab-case-slug>
description: <索引・想起判断に使う1行要約>
type: user | feedback | project | reference
---

<本文。相対日付は絶対日付に変換して書く>
```

- 1ファイル1トピック。既存トピックは新規作成せず更新する。
- `MEMORY.md` は `- [Title](file.md) — 1行フック` の一覧のみ。本文を書かない。200行未満を保つ。
- `projects/<slug>.md` は単一ファイル。肥大化したプロジェクトのみディレクトリへ昇格(YAGNI)。

### 2. ロード: SessionStart hook

`claude/hooks/inject-memory.sh`(dotfiles 追跡。`.gitignore` に `!/claude/hooks/` `!/claude/hooks/**` を追加する — 既存の追跡ファイルは ignore の対象外だが、新規ファイルは明示ホワイトリストが必要)。

動作:
1. stdin の JSON から `cwd` を取得(jq。**CRLF 対策で `tr -d '\r'` を通す** — 937ef4a と同種の問題を踏まない)。
2. slug を算出: `git -C "$cwd" remote get-url origin` が成功すれば URL 正規化 slug → 失敗すれば ghq root 相対 slug → それも不可なら path-slug(優先順の定義は「全体構成」を参照)。
3. `~/.claude/memory/MEMORY.md`(全文)と `~/.claude/memory/projects/<slug>.md`(存在すれば全文)を、用途説明の前置きと共に stdout へ出力(SessionStart の stdout はセッションコンテキストに追加される)。
4. memory ディレクトリや対象ファイルが無ければ何も出力せず exit 0(未セットアップ環境で無害)。

`claude/settings.json` の `hooks.SessionStart` に登録する。

### 3. 書き込みルール(CLAUDE.md 追記)

- **書く**: ユーザーの好み・訂正されたやり方(理由つき)・プロジェクトの確定方針や制約(コード・git 履歴から導けないもの)・外部リソースのポインタ。
- **書かない**: リポジトリが既に記録していること、一回限りのデバッグメモ、経緯・失敗談そのもの(行動を変える技術的因果だけ知見として残す)。
- 明示指示(「覚えて」)でも自発的な気づきでも書く。書いたら索引行を同期する。
- **ビルトイン記憶(`~/.claude/projects/<slug>/memory/`)は使わず、本システムに一本化する。**
- 書き込み後、記憶リポジトリ内で即 `chore(memory): <topic>` を commit し **push まで自動実行**(プライベートリポジトリのため公開リスクなし。取り消しは revert + push)。
- 記憶の commit は docs-only の定型作業として **codex-review ゲートの対象外**。
- 毎回の許可プロンプトで書き込みが億劫にならないよう、`claude/settings.json` の permissions allowlist に記憶リポジトリ限定の git コマンド(例: `git -C ~/.claude/memory` 配下の add/commit/push)を追加する。

### 4. 同期とメンテナンス

- マシン間同期: 書き込み時 auto-push。pull は手動(hook では実行しない — オフライン時・conflict 時に hook が壊れる失敗モードを避ける)。
- 整理(consolidation): 専用 skill **`memory-consolidate`** を初期実装に含める(`claude/skills/memory-consolidate/SKILL.md`、dotfiles 追跡。個人情報は含めない)。内容は本システムのレイアウトに合わせた 4 フェーズ手順:
  1. **Mine**: 直近セッションで繰り返し出た指摘・確定方針・新事実を抽出(一回限りのデバッグメモは拾わない)
  2. **Consolidate**: 既存記憶へマージ。相対日付を絶対日付化。矛盾は最新値で解決(曖昧ならユーザーへ確認)
  3. **Dedup**: 定義箇所を一つに保つ。CLAUDE.md が定めるルールを記憶側に再掲しない。存在しないファイル/シンボルへの参照を除去 or 現存確認
  4. **Prune & Index**: 索引(`MEMORY.md`)を 1 記憶 1 行・200 行未満に剪定し、実ファイル一覧と同期
  - 発動: 「記憶の整理」「dream」の指示、20〜30 セッション毎、大規模リファクタ後。
  - **整理は日常追記と別 commit にし、auto-push せず shishi のレビュー後に push**(LLM による書き換えは hallucination 混入リスクがあるため)。

### 5. セットアップ(新マシン)

setup.sh に追記: `~/dev/claude-memory`(`CLAUDE_MEMORY_DIR` で上書き可)が無ければ自動 clone を試みる(ssh → `gh repo clone` の順。認証未設定なら手動 clone を促すメッセージを出して続行)。ディレクトリが存在すれば `claude/memory` symlink を作成。プライベートリポジトリ `shishi/claude-memory` の作成は初回のみ(`gh repo create --private`)。

## エラーハンドリング

- hook: memory 不在・jq 不在・JSON 不正のいずれでも exit 0 で無出力(セッション起動を阻害しない)。
- auto-push 失敗(オフライン等): commit は残るので次回 push で回復。エラーでセッションを止めない。

## テスト

- hook 単体: 偽の stdin JSON を与え、(a) 索引+プロジェクト記憶が出力される、(b) プロジェクト記憶が無ければ索引のみ、(c) memory ディレクトリ不在で空出力・exit 0、(d) origin ありの cwd で remote slug、remote なし+ghq root 配下で ghq 相対 slug、どちらも無しで path-slug に解決される、(e) ssh 形式と https 形式の origin が同一 slug になる、(f) ghq root 配下の remote なしリポジトリの slug が、同 URL を origin に持つリポジトリの slug と一致する、を確認。
- 結合: 新セッションを起動し、注入されたコンテキストを目視確認。

## スコープ外

- hook での自動 pull
- consolidation の自動発動(スケジューラ・cron 化)— 手動トリガーのみ
- ビルトイン記憶からの過去データ移行(既存4件は少量なので必要なら手動)
