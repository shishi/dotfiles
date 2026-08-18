# Place Shared Agent Scripts under `agents`

| | |
|---|---|
| **Status** | proposed |
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

この配置判断と同時に、共有記憶を現在の運用として再確認します。Codex 利用の撤回記録は
取り消し、Codex native Memories と Claude Code auto memory は無効のまま維持します。

### Consequences

**Positive:**

* source と runtime の両方で共有責務が明確になる
* Codex が `~/.claude` の存在に依存しなくなる
* 共有実装の修正とテスト対象が 1 箇所になる

**Negative:**

* setup 前の環境では新しい `~/.agents` link が無いため hook を起動できない
* 移行時に設定、指示、テストの全参照を同時に更新する必要がある

**Neutral:**

* `claude/hooks` と `codex/hooks` にはエージェント固有 hook が引き続き残る
* private `agent-memory` repo の配置と commit protocol は変わらない

### Confirmation

setup fixture で `~/.agents/bin` と `~/.agents/hooks` の link target を確認します。全 tracked
consumer に旧 resolver/injector path が残っていないことを検索し、Claude Code と Codex の
双方から同じ injector contract test を実行します。実装完了後に status を accepted へ
変更します。

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
