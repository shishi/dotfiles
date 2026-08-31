---
name: review-gate
description: |
  レビューゲートの司令塔。key milestones — spec/PRD/plan の作成・更新直後
  (spec gate)、major 実装ステップ後(>=5 files / 新規モジュール / 公開 API /
  infra・config 変更)、および git commit / PR / merge / release の前
  (defect gate)— に、secrets / 仕様・スコープ / 正しさ(または adversarial)の
  各レーンを編成し、予算内(最大 2 周)で反復する。土日(JST)は codex エンジンを
  Claude subagent に差し替える。キーワード: レビューゲート, review gate,
  レビューして, commit 前レビュー。
---

# Review gate(司令塔)

観点(~/.claude/agents/*-reviewer.md)とエンジン(codex / Claude subagent)を分離した
多レーンレビューゲート。分岐(曜日・エンジン・レーン編成・反復)はこの skill だけが持つ。

## ゲート種別

| ゲート | トリガー | レーン |
|---|---|---|
| spec gate | spec/PRD/plan/設計 doc の作成・更新直後 | 0: secrets → adversarial |
| defect gate | major 実装後(>=5 files / 新規モジュール / 公開 API / infra・config 変更)、commit / PR / merge / release 前 | 0: secrets → 1: spec-scope + 2: correctness(並行) |

`/review-gate` 引数なしの場合: 直前に spec/plan を書いていたら spec、コード変更が
uncommitted にあれば defect。両方該当して曖昧なら質問する。

## レビュー対象の組成(gate が一元管理)

レビュー対象 = `git diff HEAD` + 全 untracked ファイルの本文
(`git status --short --untracked-files=all` で列挙)。新規モジュールは untracked が
本体になるため、diff だけでは系統的に見落とす。
- Claude エンジン(subagent)には組成済み本文をプロンプトで渡す(reviewer agent は
  Bash を持たない)
- codex エンジンには前置きで同じ組成を自分で行わせる(codex-review skill が行う)

## エンジン決定

- codex エンジンのレーン(correctness / adversarial)= **codex**(平日・CLI 健在)/
  **Claude subagent**(土日 or codex 不能)
- 曜日判定: `TZ=Asia/Tokyo date +%u` で 6 or 7 → 土日(ホストのローカル TZ に依存させない)
- spec-scope の既定は Claude subagent、secrets は常時 gitleaks(曜日無関係)
- **3 観点いずれも codex へ差し替えられる**(codex-review skill が correctness / adversarial /
  spec-scope の各モードを持つ)。spec-scope を codex で走らせる場合、前置きに足す入力は
  codex-review skill の「spec-scope モードで前置きに足す入力」に従う — タスク記述の逐語コピーが
  無ければ差し替えは成立しない
- Claude subagent エンジンでの実行 = 対応する観点 agent
  (spec-scope-reviewer / correctness-reviewer / adversarial-reviewer)を Task tool で dispatch し、
  組成済みレビュー対象と focus をプロンプトで渡す(1 パス)
- codex エンジンでの実行 = codex-review skill に観点名・focus を渡して 1 パス実行
  (secrets-scan 先行は下記手順に含まれる)

## defect gate の手順

1. 対象確認: 組成したレビュー対象が空なら「レビュー対象なし」で終了
2. 曜日判定・エンジン決定(上記)
3. レーン0: secrets-scan skill → 検出ゼロまで fix→re-scan(先行・直列。secrets 入りの
   内容を外部 API に送る前に検出する)
4. レーン1: spec-scope-reviewer(Claude)とレーン2: correctness(決定エンジン)を
   並行 dispatch(各 1 パス。反復はレーン内で回さない)
   - レーン1 の入力組成は spec-scope-review skill の「入力組成」節の規則に従う
     (タスク記述は既存テキストの逐語コピーに限る。無ければ停止してユーザーに求める)
5. 引用検証: 欠陥主張の指摘 → 少なくとも 1 つの引用がレビュー対象に存在すること
   (未変更コードからの補助引用は worktree と Read で照合)。要件未達・判断できない型の
   指摘 → 引用を要件ソースと照合。不一致は棄却し ID 付きでレポートに記録
6. **採否判定**: 指摘は採用命令ではない。現在の依頼へ直接もたらす実益または回避する
   具体的リスクを説明できる blocker/should だけ修正し、説明できない指摘は理由 1 行付きで
   棄却として記録する(CLAUDE.md の過剰化の停止条件)。採用した修正を適用 → 対象を
   再組成して **3 に戻る**(secrets-scan も毎反復再実行。反復中の修正で混入した secrets を
   素通りさせない)。同一箇所への指摘が衝突したら correctness を優先し、spec 側は
   再レビューで確認
   - **反復予算: 同一対象への再レビューは 2 周まで**(secrets レーンは対象外 — 決定的で
     単調減少するため検出ゼロまで回す)。gate の内部反復は convergence-gate hook からは
     見えないため、この上限は本 skill 自身が守る。反復の間に大きな追加実装(目安:
     編集 15 回以上)が挟まった場合は新しいマイルストーンとして数え直す
7. **通過条件**: レビューできたレーンがすべて blocker/should ゼロで、かつ未レビューのレーンが
   無いこと。ただしエラー処理のエスカレーションを段階 4 まで尽くしたレーンは、未レビューの
   ままでも通過を妨げない(その場合はレポートに明記する)。note は任意対応(未対応 note は
   レポートに記録)。通過後に note を修正した
   場合は通過確定前に 3(secrets-scan)から再実行(note 修正のみなら lane 1/2 の
   再 dispatch は省略可。secrets-scan は必須)
8. 停止判定: 反復予算(2 周)に到達して blocker/should が残る、同一指摘 2 回連続未解消、
   テスト/リンタ失敗 2 回連続、または「判断できない」多発がタスク記述の再構成
   (別の逐語ソースを探す・ユーザーに確認する。主エージェントの新規書き起こしは不可)後も
   解消しない → 残件を 1 件ずつ採否と理由付きで列挙してユーザーへ報告し停止

## spec gate の手順

defect gate の 1–3 と同様(対象は文書 diff + untracked 文書)。その後 adversarial 観点
1 レーン(エンジンは決定に従う)。findings は修正に入る前に引用検証し(棄却は [V-n]
付きで記録)、defect gate と同じ採否判定を通す。material findings の fix→re-review は
**2 周まで** — **各反復で secrets-scan も再実行**。「safe」相当の結論で通過。予算到達で
残件があれば採否と理由を列挙して停止・報告。**adversarial レーンが結果を返さない場合はエラー処理の
エスカレーションに従い、段階 4 まで尽くしたら結論が無いまま通過してよい**(defect gate と同じく
「⚠️ 未レビュー通過」として記録する)。

## エラー処理

| 障害 | 対処 |
|---|---|
| 観点レーン(spec-scope / correctness / adversarial)が結果を返さない — subagent の死亡・無応答・完了しても結果が届かない、codex の 401 / hang / timeout | 下記のエスカレーションを順に進める。**フェイルクローズしない** |
| gitleaks 不在・導入不能 | 停止してユーザーへ報告(素通り禁止)。**下記のエスカレーションは観点レーン限定で、secrets レーンには適用しない** — 検査なしで通すと public repo へ secrets が入る経路が無検査になる |
| タスク記述が無い/曖昧 | 別の既存逐語ソースを探す or ユーザーに確認。新規書き起こしで代用しない |
| diff 巨大(>10 ファイルかつ互いに独立) | focus で範囲を分けて複数回。同一パターンの繰り返しなら分割不要 |

### 観点レーンのエスカレーション

結果が届かないレーンごとに、次を順に進める。**明示的な失敗(エラー応答・非ゼロ終了)は待たずに
次の段階へ移る。** 待つのは無応答のときだけで、待ちは**その試行の dispatch が受理された時点から
5 分**を上限とする。上限を置くのは、待ち時間を都度の判断に任せるとゲートの厳しさが実行のたびに
変わるからである。

1. 初回の試行を dispatch し、受理から最大 5 分待つ
2. **同じエンジンへ同じ入力で新しく dispatch し**(既存 agent の再開ではない)、受理から最大 5 分待つ
3. もう一方のエンジンへ差し替えて新しく dispatch し、受理から最大 5 分待つ。観点は
   `~/.claude/agents/*-reviewer.md` が単一ソースなので、エンジンを替えても観点は変わらない。
   **差し替えに必要な入力を組めないレーンはこの段階を飛ばす**(spec-scope をタスク記述の
   逐語コピー無しで走らせることはできない)
4. それでも結果が無ければ、**そのレーンを未レビューのまま通過させる。** レポートの
   ステータスを「⚠️ 未レビュー通過」にし、どのレーンをどの段階まで試したかを書く

codex エンジンの試行では codex-review skill が内部で 1 リトライを持つ。**その内部リトライは
段階 2 に数えない** — 内部リトライまで含めて 1 つの試行として扱う。

## 最終レポート

```
## Review gate 結果
- ゲート: defect | spec / エンジン: codex | claude(理由: 週末 / codex 不能)
- 反復: レーン別 X 回 / ステータス: ✅ 通過 | ⚠️ 未レビュー通過 | ⚠️ 膠着停止
- 修正した指摘: [ID] と要約
- 棄却した指摘: [ID] + 理由(引用不一致 等)
- 未対応 note: [ID]
- 省略・代替したレーン: 理由込みで必ず明記(土日の codex 代替は毎回ここに書く)
```

## 他のレビュー機構との関係

- openai-codex plugin(/codex:review 等)と plugin の stop 時レビューゲートは使わない。
  この skill が唯一のゲート
- superpowers の per-task レビュー(subagent-driven 実行中)とは共存する。per-task
  レビュー済みでも本 gate は省略しない(高度が違う: per-task = 実装中の早期検出、
  本 gate = 節目の最終防衛線)
- 記憶 repo(agent-memory)への commit は本 gate の対象外(CLAUDE.md の規定)
