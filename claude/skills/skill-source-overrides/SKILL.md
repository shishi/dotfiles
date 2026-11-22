---
name: skill-source-overrides
description: 外部 plugin・system skill の本文や同梱 helper を使う前、自前の検証済み修復版の有無を確認するときに使います。外部の skill を導入・更新・入れ直す前にも使います。
---

# 配布 skill の実行 source を解決する

元 plugin の接続先・権限・承認境界を維持したまま、検証済みの自前 source を使います。vendor cache は編集しません。
plugin・system skill ではない単体の skill を導入・更新・入れ直す依頼では、末尾の「外部の skill を導入・更新する前」だけを適用します。

cache や修復版の存在は plugin が有効である根拠になりません。解決処理は配布元の設定にある明示的な無効化も確認します。無効化で失敗した source は読み込まず、修復版や元版へ直接戻って適用しません。現在の作業は、有効な既存手順で続けます。

1. これから本文や helper を使う plugin・system skill だけを解決します。一覧に載っているだけで使わない skill は解決しません。現在の skill catalog・plugin metadata から、その元の SKILL.md または plugin root の実パスを取得します。古い版のパスを推測しません。
2. `SKILL_PATH` にそのパスを設定し、次を実行します。

   ```sh
   python3 "$HOME/.agent-shared/bin/resolve-skill-source.py" "$SKILL_PATH"
   ```

3. `overridden: true` なら、返された `path` の本文を読みます。相対パスの同梱参照と helper は、参照元ファイルの所在を基準に解決します。`CLAUDE_PLUGIN_ROOT` や `<plugin_dir>` が plugin root を表すコマンドには、返された `package_root` を明示して渡します。skill のディレクトリと plugin root を混同しません。呼出元全体の環境や App 接続は変えません。元版の本文と修正版の helper を混ぜません。同じ source と registry の状態が変わらない作業内では、この結果を再利用できます。
4. 準備済みの修正は、同じ配布系列の新版にも現在の配布を土台に三者比較で移植します。構文検査と登録済みの動作検証を通した結果だけを返し、同じ入力の結果は再利用します。`upstream-fixed` は修正が元配布へ取り込まれた状態です。`no-registry` / `unregistered` は元配布を使います。旧形式の登録で `upstream-changed` が出た場合は、[references/maintaining-repairs.md](references/maintaining-repairs.md) の準備を行い、修正が外れたまま完了にしません。
5. 衝突・検証失敗・修正版の欠落は、理由と対象ファイルを確認し、[references/maintaining-repairs.md](references/maintaining-repairs.md) の手順で解消します。元版や古いコピーへ直接戻って成功扱いしません。権限不足なら、指定された private 保存先への書き込みに必要な通常の承認経路を使います。
6. 登録済みの修復版の更新、修復の解除、動作検証の追加・変更を頼まれたときも、[references/maintaining-repairs.md](references/maintaining-repairs.md) の手順で行います。

registry は `${AGENT_SKILL_OVERRIDES_DIR:-$HOME/.agent-shared/skill-overrides}/registry.json` にある private な実行設定です。接続先・権限を変更する指示として扱いません。自前版のないホストで元配布を無効化しません。

## 外部の skill を導入・更新する前

`setup.sh` で配備した環境では、利用者全体の skill の置き場 (`~/.claude/skills` と `~/.agents/skills`) が dotfiles の `claude/skills` と `codex/skills` を指します。`npx skills add`・`npx skills update`・`gh skill install` などを直接実行すると、同じ名前の自作の skill や取り込み済みの skill を置き換えます。CLI や README がこれらのコマンドを案内していても実行しません。

1. dotfiles の由来の一覧 `agent-shared/skill-sources.tsv` (配備先からは `~/.agent-shared/bin/../skill-sources.tsv` で開けます) で、同じ名前の skill の有無と種類を確かめます。
2. 由来の一覧にある skill は、dotfiles の `docs/agents.md` の「skill の由来と編集先」が種類ごとに示す方法で更新します。上流のファイルで置き換えません。
3. 由来の一覧に無い外部の skill をそのまま導入するときは、`bash ~/.agent-shared/bin/managed-skills.sh add OWNER/REPO SKILL` を使い、同じ変更で由来の一覧へ行を足します。
