# Place Shared Agent Scripts under `agents`

| | |
|---|---|
| **Status** | accepted |
| **Date** | 2026-08-18 |
| **Decision-makers** | shishi |
| **Consulted** | Codex |
| **Informed** | Claude Code and Codex configuration maintainers |

## Context and Problem Statement

Claude Code と Codex は同じ memory resolver と injector を使います。しかし、resolver は
repository root、injector は `claude/hooks/` にあり、配置が共有責務を表していません。
Codex が Claude Code のホームを経由する runtime path も、片方の構成変更が他方を壊す
不要な依存です。

## Decision Drivers

* 共有責務が source tree と runtime path から判別できること
* Claude Code と Codex のどちらにも所有権を寄せないこと
* 既存の `~/.agents/skills` と一貫した配備方法を使うこと
* 互換 wrapper や重複コピーによる恒久的な保守負担を増やさないこと
* agent-memory を両エージェントの唯一の永続記憶として維持すること

## Considered Options

1. `agents/bin` と `agents/hooks` に分ける
2. `agents/common/bin` と `agents/common/hooks` に分ける
3. 現在の配置を維持し、Codex から Claude Code 側を参照する

## Decision Outcome

**Chosen option**: "`agents/bin` と `agents/hooks` に分ける"。`agents` 自体が共有境界を
表すため、追加の `common` 階層は意味を増やしません。resolver と hook は用途別に分け、
`setup.sh` が `~/.agents/bin` と `~/.agents/hooks` を source directory へリンクします。

Claude Code と Codex は `~/.agents/hooks/inject-memory.sh` を共有し、それぞれの memory
link を引数で渡します。配置解決は `~/.agents/bin/resolve-memory-dir.sh` を使います。
既存の旧パスは同一変更で全 consumer を移行し、互換 wrapper は残しません。

`~/.agents/bin/memory-write-lock.sh` も共有します。`acquire` が返す opaque handle
（内部の owner token を含まない handle path）を同じ workflow の tool call 間で保持します。
`release` は handle と owner marker を再検証し、取得者の lock だけを解放します。

injector は `main^{commit}` を固定し、その snapshot からだけ記憶を読みます。
snapshot の解決、object の読み取り、秘密情報検査のいずれかが失敗した場合は、
worktree へ fallback せず記憶本文を出力しません。

この配置判断と同時に、共有記憶を現在の運用として再確認します。Codex 利用の撤回記録は
取り消し、Codex native Memories と Claude Code auto memory は無効のまま維持します。

### Consequences

**Positive:**

* source と runtime の両方で共有責務が明確になる
* Codex が `~/.claude` の存在に依存しなくなる
* 共有実装の修正とテスト対象が 1 箇所になる
* branch 切り替えや worktree 編集中でも `main` snapshot 以外を注入しない
* process と tool call をまたいでも lock の取得者を検証できる

**Negative:**

* setup 前の環境では新しい `~/.agents` link が無いため hook を起動できない
* 移行時に設定、指示、テストの全参照を同時に更新する必要がある
* snapshot または検査の異常時は記憶本文を省略し、復旧警告だけを出力する
* lock の解放失敗時は state を自動削除せず、確認後の復旧が必要になる

**Neutral:**

* `claude/hooks` と `codex/hooks` にはエージェント固有 hook が引き続き残る
* private `agent-memory` repo の配置と `main` への commit / push protocol は変わらない

### Confirmation

実装は次の確認を通過しています。

```bash
for test_file in tests/*.sh; do bash "$test_file" || exit 1; done
for test_file in agents/hooks/*.test.sh; do bash "$test_file" || exit 1; done
bash -n agents/bin/*.sh agents/hooks/*.sh setup.sh tests/*.sh codex/hooks/*.sh claude/hooks/*.sh
jq -e . claude/settings.json codex/hooks.json >/dev/null
codex features list | rg '^memories[[:space:]]+stable[[:space:]]+false$'
```

setup fixture は `~/.agents/bin` と `~/.agents/hooks` の link target を確認します。
injector と memory helper の suite は commit snapshot、秘密らしい内容の非注入、lock の
所有権、dirty worktree の拒否、指定した path だけの publish を確認します。旧 path の
不在や agent 固有設定の全文は standing test で固定せず、関連変更時に直接確認します。

macOS 環境に `pwsh` が無かったため、PowerShell 固有テストは未実行です。
共有 hooks JSON contract は Bash と `jq` で確認しています。

## Pros and Cons of the Options

### `agents/bin` と `agents/hooks` に分ける

* Good, because `agents` だけで共有範囲を表現できる
* Good, because executable helper と lifecycle hook の用途を区別できる
* Good, because `~/.agents/skills` と同じ配備単位を再利用できる
* Bad, because runtime link が 2 つ増える

### `agents/common/bin` と `agents/common/hooks` に分ける

* Good, because 共有物であることを明示できる
* Bad, because `agents` と `common` が同じ意味を重ね、path だけを長くする

### 現在の配置を維持する

* Good, because ファイル移動が不要
* Bad, because 共有 injector が Claude Code 所有に見える
* Bad, because Codex の起動が `~/.claude` の配備状態に依存する

## More Information

詳細な安全性、移行、テスト要件は
[`2026-08-18-shared-agent-memory-hardening-design.md`](../superpowers/specs/2026-08-18-shared-agent-memory-hardening-design.md)
に記録します。
