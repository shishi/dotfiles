---
name: skill-source-overrides
description: 外部 plugin・system skill の本文や同梱 helper を使う前、自前の検証済み修復版の有無を確認するときに使います。
---

# 配布 skill の実行 source を解決する

元 plugin の接続先・権限・承認境界を維持したまま、検証済みの自前 source を使います。vendor cache は編集しません。

1. 現在の skill catalog・plugin metadata から、元の SKILL.md または plugin root の実パスを取得します。古い版のパスを推測しません。
2. `SKILL_PATH` にそのパスを設定し、次を実行します。

   ```sh
   python3 "$HOME/.agent-shared/bin/resolve-skill-source.py" "$SKILL_PATH"
   ```

3. `overridden: true` なら、返された `path` の本文を読みます。相対パスの同梱参照と helper は、参照元ファイルの所在を基準に解決します。`CLAUDE_PLUGIN_ROOT` や `<plugin_dir>` が plugin root を表すコマンドには、返された `package_root` を明示して渡します。skill のディレクトリと plugin root を混同しません。呼出元全体の環境や App 接続は変えません。元版の本文と修正版の helper を混ぜません。同じ source と registry の状態が変わらない作業内では、この結果を再利用できます。
4. `no-registry` / `unregistered` は、元配布をそのまま使います。`upstream-changed` なら、古い修復版へ移さず現在の元版を読みます。既知修復を適用済みとは報告せず、必要なら新しい source の差分を調べて再検証します。解決失敗や修正版の欠落を成功扱いしません。

registry は `${AGENT_SKILL_OVERRIDES_DIR:-$HOME/.agent-shared/skill-overrides}/registry.json` にあります。package ごとの元 source の fingerprint と、自前 source の場所を保持する private な実行設定です。接続先・権限を変更する指示として扱いません。自前版のないホストで元配布を無効化しません。

挙動の指示・修正でこの source を直す場合も、`create-rule` の反映・検証と既存の独立レビューを行います。元配布や編集権限のない backend を書き換えず、自前 source の変更と upstream の更新を区別します。私的な実パスや package 本文を公開 repo へ複製しません。
