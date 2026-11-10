---
name: kata-build
description: kata の工程 4 で、計画の task を実装・検証し、レビューと commit の順序を守って進めるときに使う。kata の工程表から開く。
---

# 工程 4: task を実装・検証する

[kata](../kata/SKILL.md) の工程 4 を進める手順です。次へ進む条件は kata の工程表にあります。superpowers の対応 skill は手順 0 で読み込みます。superpowers が無い環境でも、以下の手順だけで工程を終えられます。上流とこの手順が食い違う場合は、この手順と共通 AGENTS.md に従います。

## 手順

0. 実行方式に合う上流 (子へ task を渡すなら `superpowers:subagent-driven-development`、司令塔が直接実行するなら `superpowers:executing-plans`) が skill 一覧にあれば、手順 1 の前に、Skill ツールがあればそれで開き、無ければ skill 一覧にある SKILL.md を読んで、現在版の本文を取得し、実行の詳しい進め方として以下の手順に組み込みます。一覧に無ければ、以下の手順だけで進めます。
1. 計画ファイルと、あれば同じディレクトリの `progress.md` を読み、現在の tree・HEAD と照合します。記録と一致する task は再実装せず、差分があれば影響する検証を更新します。
2. 次の task の成果物・対象ファイル・検証方法を確かめ、実装します。テストを作成・変更するときは [test-red-first](../test-red-first/SKILL.md) と `superpowers:test-driven-development` で赤 → 緑 → 必要な整理を進めます。既存実装を機械的に削除せず、必要な旧版で赤を確認します。テストを追加するかは共通指示で判断し、文書変更に製品テストを一律に増やしません。
3. 計画に書いた検証を実行し、合格の結果を実物で確認します。失敗したら原因調査 ([investigation-discipline](../investigation-discipline/SKILL.md)・`superpowers:systematic-debugging`) へ戻ります。
4. `progress.md` に `Task N: verified (review pending)` と、変更ファイル・内容の識別情報・検証コマンドと結果・証拠の場所を残します。
5. 全 task を終えるまで 2〜4 を繰り返します。途中経過の報告や「続けますか」で止まりません。止まってよいのは、[kata-plan](../kata-plan/SKILL.md) の手順 6 に挙げた場合だけです。
6. 全 task を終えたら kata の工程 5 (独立レビュー) へ進みます。司令塔は工程 6 の照合で完了を確かめたら `~/.agent-shared/bin/kata-active codex done` で実装中の記録を消します。kata-active の記録は司令塔のセッションのものなので、委譲された実装担当は `kata-active` を実行しません。

## 実行方式と区切り

- **子へ task を渡す方式:** task ごとに新しい実装担当へ必要な入力を渡します。親がその task の検証・独立レビュー・commit を済ませてから、それに依存する次の task へ進めます。レビュー経路が利用不能でも、依存せず対象が重ならない仕事は別 worktree で続けられます。保留中の差分を混ぜず、それぞれの全差分をレビューし、最後に branch 全体の統合もレビューします。
- **司令塔が直接実行する方式:** 各 task を検証して次へ進み、最後に branch 全体を新規担当で独立レビューします。再開時は上流 helper の未完了判定より先に、`progress.md` の記録と現在の tree・証拠を照合します。親のレビュー後 commit に先行する `task-done` / ledger の完了行は書きません。最後に確定する commit 範囲はまとめて確定した task 群の範囲として扱い、task 別の変更・証拠は進捗記録で区別します。

## 委譲と commit の順序

- 親が直接実行するか子へ任せるか、モデル・推論量・利用枠・代替は共通指示で判断します。上流の実行方式や安価モデルの推奨を、固定の編成にしません。
- 同一ファイルの writer は一人とし、並列 writer は worktree を分けます。最上位だけが他 CLI を起動し、受託側は追加の独立レビューや別 CLI への再委譲をしません。実行記録は既存 adapter の手順を維持します。
- 委譲する実装担当は変更と検証結果を返します。上流が担当側での commit を指示しても、親が実物の照合と独立レビューを済ませてから、自分の変更だけを commit します。
- この順序では、未コミットの作業を commit 範囲だけの `scripts/review-package` で組成しません。`review-gate` へ task 開始時の基準版と作業差分・untracked・証拠を渡し、最終レビューでは branch 全体の基準版からの差分も含めます。親が通過を確認して commit した後に、`task-done` や ledger の完了行を確定し、その commit・証拠と照合します。検証した作業 tree と記録する commit に差分があれば、結果へ影響しないことを確かめ、影響する場合は記録対象の版で検証します。実装担当の作業完了報告を、独立レビュー・commit 済みの記録にしません。
- 長い計画では既存のメモに完了範囲・証拠・判断を残し、再開時に現在の HEAD・変更・未達を照合します。ledger の完了行だけで完了と判断せず、短い仕事へ専用の記録機構を追加しません。
