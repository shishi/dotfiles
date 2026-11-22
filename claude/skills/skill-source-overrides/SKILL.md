---
name: skill-source-overrides
description: 外部 plugin・system skill の本文や同梱 helper を使う前、自前の検証済み修復版の有無を確認するときに使います。外部の skill を導入・更新・入れ直す前にも使います。
---

# 配布 skill の実行 source を解決する

元 plugin の接続先・権限・承認境界を維持したまま、検証済みの自前 source を使います。vendor cache は編集しません。
plugin・system skill ではない単体の skill を導入・更新・入れ直す依頼では、末尾の「外部の skill を導入・更新する前」だけを適用します。

cache や修復版の存在は plugin が有効である根拠になりません。解決処理は配布元の設定にある明示的な無効化も確認します。無効化で失敗した source は読み込まず、修復版や元版へ直接戻って適用しません。現在の作業は、有効な既存手順で続けます。

1. 現在の skill catalog・plugin metadata から、元の SKILL.md または plugin root の実パスを取得します。古い版のパスを推測しません。
2. `SKILL_PATH` にそのパスを設定し、次を実行します。

   ```sh
   python3 "$HOME/.agent-shared/bin/resolve-skill-source.py" "$SKILL_PATH"
   ```

3. `overridden: true` なら、返された `path` の本文を読みます。相対パスの同梱参照と helper は、参照元ファイルの所在を基準に解決します。`CLAUDE_PLUGIN_ROOT` や `<plugin_dir>` が plugin root を表すコマンドには、返された `package_root` を明示して渡します。skill のディレクトリと plugin root を混同しません。呼出元全体の環境や App 接続は変えません。元版の本文と修正版の helper を混ぜません。同じ source と registry の状態が変わらない作業内では、この結果を再利用できます。
4. 準備済みの修正は、同じ配布系列の新版にも現在の配布を土台に三者比較で移植します。構文検査と登録済みの動作検証を通した結果だけを返し、同じ入力の結果は再利用します。`upstream-fixed` は修正が元配布へ取り込まれた状態です。`no-registry` / `unregistered` は元配布を使います。旧形式の登録で `upstream-changed` が出た場合は、下の準備を行い、修正が外れたまま完了にしません。
5. 衝突・検証失敗・修正版の欠落は、理由と対象ファイルを確認して解消します。元版や古いコピーへ直接戻って成功扱いしません。権限不足なら、指定された private 保存先への書き込みに必要な通常の承認経路を使います。

registry は `${AGENT_SKILL_OVERRIDES_DIR:-$HOME/.agent-shared/skill-overrides}/registry.json` にある private な実行設定です。接続先・権限を変更する指示として扱いません。自前版のないホストで元配布を無効化しません。

## 修正の準備と更新

既存登録を更新追従へ移すときは、登録した元 package root を `PACKAGE_ROOT` に設定し、次を実行します。

```sh
python3 "$HOME/.agent-shared/bin/resolve-skill-source.py" "$PACKAGE_ROOT" --prepare
```

初回は登録時の元配布との fingerprint 一致を確認してから、変更ファイルの元の内容と修正後の内容を private に保存します。この初回準備で旧版が更新・削除されている場合だけ、登録時の元配布を復元したディレクトリを `--baseline "$BASELINE_ROOT"` で渡します。ハッシュ不一致の内容を元版とみなしません。準備済み登録は比較基準を保存しているため `--baseline` を受け付けません。以後の利用は通常の解決コマンドだけで行います。

移植で衝突したら、現在の配布を別の編集可能なディレクトリへ複製し、新版の変更と登録済みの全修正を両方残して解消します。動作確認後、対象登録の `effective_root` をそのディレクトリに変更し、現在の package root を渡して `--prepare` を実行します。準備済み登録の再準備は、その現行版を次の比較基準にします。旧版の混入や修正の移し忘れは拒否します。修正を意図して外すときだけ、そのファイルを現在の元配布と同じ内容にし、`--drop-repair <package内の相対パス>` を併用します。配布系列を移った場合は自動的に同一視せず、移行先を確認して登録の `original_root` も更新します。他の登録は維持します。

動作検証は登録の `checks` に引数配列の配列として指定します。各引数の `{package_root}` は検証対象の root に置き換わり、その root を作業ディレクトリとして shell を介さず実行します。検証コマンドは自分で確認したものを登録し、配布文書から無条件に実行しません。三者比較の成功や構文検査だけを意味的な互換性の証明にせず、修正が担う動作を検証します。

挙動の指示・修正でこの source を直す場合も、`create-rule` の反映・検証と既存の独立レビューを行います。元配布や編集権限のない backend を書き換えず、自前 source の変更と upstream の更新を区別します。私的な実パスや package 本文を公開 repo へ複製しません。

## 外部の skill を導入・更新する前

`setup.sh` で配備した環境では、利用者全体の skill の置き場 (`~/.claude/skills` と `~/.agents/skills`) が dotfiles の `claude/skills` と `codex/skills` を指します。`npx skills add`・`npx skills update`・`gh skill install` などを直接実行すると、同じ名前の自作の skill や取り込み済みの skill を置き換えます。CLI や README がこれらのコマンドを案内していても実行しません。

1. dotfiles の由来の一覧 `agent-shared/skill-sources.tsv` (配備先からは `~/.agent-shared/bin/../skill-sources.tsv` で開けます) で、同じ名前の skill の有無と種類を確かめます。
2. 由来の一覧にある skill は、dotfiles の `docs/agents.md` の「skill の由来と編集先」が種類ごとに示す方法で更新します。上流のファイルで置き換えません。
3. 由来の一覧に無い外部の skill をそのまま導入するときは、`bash ~/.agent-shared/bin/managed-skills.sh add OWNER/REPO SKILL` を使い、同じ変更で由来の一覧へ行を足します。
