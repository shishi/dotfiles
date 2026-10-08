---
name: review-gate
description: |
  コード・設定・文書・issue などの作成・変更で、リスクに関わらず原則発動する
  レビューゲート。仕様・計画・設計の作成・更新直後、実装・文書の完成時、
  issue の投稿・更新前、commit / PR / merge / release 前に使う。
  省略は小規模で誤りが混入しない確信度が非常に高く、明らかに不要な場合だけ。
  secrets / 仕様・スコープ / 正しさ(または adversarial)の各レーンを編成し、
  全対象の確認と残件解消まで追跡する。Claude Code では土日(JST)に
  codex エンジンを Claude subagent に差し替え、Codex では全レーンを新規 agent で回す。
  キーワード: レビューゲート, review gate, レビューして, commit 前レビュー。
---

# Review gate(司令塔)

観点(~/.claude/agents/*-reviewer.md が単一ソース。Codex では同名の
~/.codex/agents/*-reviewer.toml が同じ本文を持ち、tests/reviewer-agents-sync.sh がドリフトを検出する)とエンジン(codex CLI / Claude subagent /
Codex 新規 agent)を分離した多レーンレビューゲート。Claude Code と Codex の両方で同じ
レーン構成・反復・通過条件を使い、分岐(実行環境・曜日・エンジン・レーン編成・反復)は
この skill だけが持つ。

## 起動と照合の基準

AGENTS.md に従い、コード・設定・文書・issue などの作成・変更で原則発動する。
具体的リスクの存在は発動の前提にしない。省略できるのは、小規模で、間違いが混入しない
確信度が非常に高く、明らかにレビューを必要としない場合だけ。
文書だけ・設定一つ・低リスクという理由だけでは省略せず、判断に迷う場合は発動する。

起動したレビューには、元の依頼と後続の訂正を両方渡す。訂正箇所だけ直して元の成果物を
失っていないか照合する。文書の読者・用途・公開可否・Git 管理は
[writing-prose](../writing-prose/SKILL.md) の基準で区別する。
失敗対策を求められた変更は、記憶更新や説明の有無ではなく、対象の修正と直接検証の結果で判定する。
主エージェントは AGENTS.md の「全範囲の完遂」に従い、依頼全体の照合を担う。
レーンの分担・focus・指摘ゼロは依頼の範囲を狭めない。必要な対象を分割した場合は
全分割の結果を揃え、分割間の依存も確認してから通過を判定する。

## ゲート種別

| ゲート | トリガー | レーン |
|---|---|---|
| spec gate | spec/PRD/plan/設計 doc の作成・更新直後 | 0: secrets → adversarial |
| defect gate | 実装・設定変更・一般文書の完成時、issue の投稿・更新前、主要な実装ステップ後、commit / PR / merge / release 前 | 0: secrets → 1: spec-scope + 2: correctness(並行) |

仕様・計画・設計を扱う文書・issue は spec gate、その他の成果物は defect gate で扱う。
外部へ投稿・更新する本文は、送信前にレビューする。
`/review-gate` 引数なしでもこの区別で選ぶ。対象が両方にまたがり曖昧なら質問する。

## レビュー対象の組成(gate が一元管理)

レビュー対象 = `git diff HEAD` + 全 untracked ファイルの本文
(`git status --short --untracked-files=all` で列挙) + Git 外で作成・変更する成果物の本文。
issue や外部文書は投稿・更新予定の全文を含め、更新なら取得した変更前の本文も添える。
Git 差分が空でも、これらの成果物があれば「レビュー対象なし」にしない。
新規モジュールは untracked が本体になるため、diff だけでは系統的に見落とす。
- 新規 agent エンジン(Claude subagent / Codex 新規 agent)には組成済み本文をプロンプトで
  渡す(reviewer agent は書き込みも Bash も持たない)
- codex CLI エンジンには Git 差分と untracked の取得を指示し、Git 外の成果物の本文は
  codex-review skill の全モード共通の追加入力として前置きに渡す
- 差分だけで要件を判定できない場合は、成果物の本文・現在状態・検証の実行結果も添える。
  会話で渡す調査結果や文書も成果物として渡す。実装者の判断過程や自己評価は証拠に含めない。

## エンジン決定

**Codex で動作中**: 全観点レーンを Codex の新規 agent(`~/.codex/agents/` の
spec-scope-reviewer / correctness-reviewer / adversarial-reviewer)で実行する。codex-review skill と
曜日判定は使わない。secrets は常時 gitleaks。以下の曜日・codex CLI の分岐は Claude Code だけのもの。

**Claude Code で動作中**:

- codex エンジンのレーン(correctness / adversarial)= **codex**(平日・CLI 健在)/
  **Claude subagent**(土日 or codex 不能)
- 曜日判定: `TZ=Asia/Tokyo date +%u` で 6 or 7 → 土日(ホストのローカル TZ に依存させない)
- spec-scope の既定は Claude subagent、secrets は常時 gitleaks(曜日無関係)
- **3 観点いずれも codex へ差し替えられる**(codex-review skill が correctness / adversarial /
  spec-scope の各モードを持つ)。spec-scope を codex で走らせる場合、前置きに足す入力は
  codex-review skill の「spec-scope モードで前置きに足す入力」に従う — タスク記述の逐語コピーが
  無ければ差し替えは成立しない
- 新規 agent エンジンでの実行 = 対応する観点 agent
  (spec-scope-reviewer / correctness-reviewer / adversarial-reviewer)を Claude Code では Task tool、
  Codex では spawn agent で dispatch し、組成済みレビュー対象と focus をプロンプトで渡す(1 パス)
- codex エンジンでの実行 = codex-review skill に観点名・focus を渡して 1 パス実行
  (secrets-scan 先行は下記手順に含まれる)

## defect gate の手順

1. 対象確認: 組成したレビュー対象が空なら「レビュー対象なし」で終了
2. エンジン決定(上記。Claude Code では曜日判定を含む)
3. レーン0: secrets-scan skill → 検出ゼロまで fix→re-scan(先行・直列。secrets 入りの
   内容を外部 API に送る前に検出する)。Git 外の成果物もローカルの一時ファイルへ保存し、
   同 skill の per-file 検査に含める。Git repo がない場合は成果物のファイルを直接検査する
4. レーン1: spec-scope-reviewer(新規 agent)とレーン2: correctness(決定エンジン)を
   並行 dispatch(各 1 パス。反復はレーン内で回さない)
   - 文書・issue では、要件との一致に加え、事実・参照先・手順・記述間の整合性を確認する
   - レーン1 の入力組成は spec-scope-review skill の「入力組成」節の規則に従う
     (タスク記述は既存テキストの逐語コピーに限る。無ければ停止してユーザーに求める)
5. 引用検証: 欠陥主張の指摘 → 少なくとも 1 つの引用がレビュー対象に存在すること
   (未変更コードからの補助引用は worktree と Read で照合)。要件未達・判断できない型の
   指摘 → 引用を要件ソースと照合。不一致は棄却し ID 付きでレポートに記録
6. **採否判定**: 指摘は採用命令ではない。現在の依頼へ直接もたらす実益または回避する
   具体的リスクを説明できる blocker/should だけ修正し、説明できない指摘は理由 1 行付きで
   棄却として記録する(AGENTS.md の過剰化の停止条件)。採用した修正を適用 → 対象を
   再組成して **3 に戻る**(secrets-scan も毎反復再実行。反復中の修正で混入した secrets を
   素通りさせない)。同一箇所への指摘が衝突したら correctness を優先し、spec 側は
   再レビューで確認
   - 再レビューに固定の総量上限を設けない。修正・新しい証拠・原因仮説に基づいて進め、
     反復の収束は AGENTS.md に従う。回数到達で必要な修正や確認を打ち切らない。
7. **通過条件**: 必要な全レーン・全対象の確認結果があり、採用した blocker/should が
   すべて解消し、全要件が証拠付きで満たされていること。未レビュー・未確認・判定不能は
   1 件でも残れば通過しない。棄却した指摘には根拠を残す。note は元の依頼の未達を含まない
   任意改善に限る。通過後に変更した場合は 3 から再実行し、変更の影響を受ける観点を再確認する。
8. 判定不能は不足する元の要件・実物・検証結果を取得して再判定する。判断過程の書き起こしで
   代用しない。自力で解消できる間は作業を続ける。権限・外部障害・本人の判断、または
   AGENTS.md の収束規約で止まる場合は、依存しない作業を済ませ、残件・試したこと・
   再開条件を報告する。停止は未完了であり、通過ではない。

## spec gate の手順

defect gate の 1–3 と同様(対象は文書 diff + untracked 文書 + Git 外の仕様・計画・設計本文)。
その後 adversarial 観点
1 レーン(エンジンは決定に従う)。findings は修正に入る前に引用検証し(棄却は [adversarial-n]
付きで記録)、defect gate と同じ採否判定・収束規約を適用する。必要な修正後は
secrets-scan と関連箇所の再レビューを行う。全対象のレビュー結果が「safe」相当で、
主エージェントが元の全要件との照合を完了した場合だけ通過する。
結果が届かない場合は下記のエスカレーションを行い、未レビューのまま通過させない。

## エラー処理

| 障害 | 対処 |
|---|---|
| 観点レーン(spec-scope / correctness / adversarial)が結果を返さない — subagent の死亡・無応答・完了しても結果が届かない、codex の 401 / hang / timeout | 下記のエスカレーションで回復を試みる。結果なしでは通過しない |
| gitleaks 不在・導入不能 | 停止してユーザーへ報告(素通り禁止)。**下記のエスカレーションは観点レーン限定で、secrets レーンには適用しない** — 検査なしで通すと public repo へ secrets が入る経路が無検査になる |
| タスク記述が無い/曖昧 | 別の既存逐語ソースを探す or ユーザーに確認。新規書き起こしで代用しない |
| diff 巨大(>10 ファイルかつ互いに独立) | focus で範囲を分けて複数回。同一パターンの繰り返しなら分割不要 |

### 観点レーンのエスカレーション

結果が届かないレーンごとに、次を順に進める。**明示的な失敗(エラー応答・非ゼロ終了)は待たずに
次の段階へ移る。** 待つのは無応答のときだけで、待ちは**その試行の dispatch が受理された時点から
5 分**を上限とする。上限を置くのは、待ち時間を都度の判断に任せるとゲートの厳しさが実行のたびに
変わるからである。

1. 初回の試行を dispatch し、受理から最大 5 分待つ
2. 失敗原因を確認し、一過性の障害など再試行の根拠があれば新しく dispatch する。
   実行中の agent は観測タイムアウトだけで失敗とせず、同じ handle の状態を確認する。
   新しい試行を受理した場合は最大 5 分待つ
3. もう一方のエンジンへ差し替えて新しく dispatch し、受理から最大 5 分待つ。観点は
   `~/.claude/agents/*-reviewer.md` が単一ソースなので、エンジンを替えても観点は変わらない。
   **差し替えに必要な入力を組めないレーンはこの段階を飛ばす**(spec-scope をタスク記述の
   逐語コピー無しで走らせることはできない)。Codex にはエンジンが 1 つしか無いので、この段階は
   常に飛ばす
4. それでも結果が無ければ、そのレーンは未レビューのまま保持し、ゲートは未通過とする。
   依存しない作業を済ませ、試行結果と再開に必要な条件を報告する。独立レビューが必要な
   レーンを自己レビューで代替せず、必要な結果が揃うまで通過を宣言しない。

codex エンジンの試行では codex-review skill が内部で 1 リトライを持つ。**その内部リトライは
段階 2 に数えない** — 内部リトライまで含めて 1 つの試行として扱う。

## 最終レポート

```
## Review gate 結果
- ゲート: defect | spec / エンジン: codex | claude(理由: 週末 / codex 不能)| codex-agent
- 反復: レーン別 X 回 / ステータス: ✅ 通過 | ⚠️ 未通過(未完了)
- 全対象・全要件の確認結果と根拠 / 未確認・判定不能・未レビューの対象
- 修正した指摘: [<レーン>-n] と要約
- 棄却した指摘: [<レーン>-n] + 理由(引用不一致 等)
- 未対応 note: [<レーン>-n]
- 省略・代替したレーン: 理由込みで必ず明記(土日の codex 代替は毎回ここに書く)
```

## 他のレビュー機構との関係

- openai-codex plugin(/codex:review 等)と plugin の stop 時レビューゲートは使わない。
  この skill が唯一のゲート
- superpowers の per-task レビュー(subagent-driven 実行中)とは共存する。per-task
  レビュー済みでも本 gate は省略しない(高度が違う: per-task = 実装中の早期検出、
  本 gate = 節目の最終防衛線)
- 記憶 repo(agent-memory)への commit は本 gate の対象外(AGENTS.md の規定)
