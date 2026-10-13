---
name: scoop-manifest
description: Scoop manifest の checkver・autoupdate・hash・extract_dir を変更するときや、その自動更新の不具合を調べるときに使います。通常の Scoop インストール・利用だけでは使いません。
---

# Scoop manifest の更新と検証

インストールが読む値、更新テンプレート、配布アーカイブの実物を照合します。実行中の Scoop と bucket の版を確認し、実装に依存する判断はその版のソースで確かめます。

## 更新経路を再現する

1. 対象 manifest の正本と未コミット変更を確認します。対応する全 architecture の `url`・`hash`・`extract_dir` と `autoupdate` の配置を列挙します。
2. 対象 manifest と必要な補助ファイルを一時ディレクトリへコピーします。既存の `checkver.ps1` を使い、`-Dir` がコピー先の絶対パスであることを確認します。
3. コピーに対して `checkver.ps1 -Dir <コピー先> -App <対象名> -Update -ForceUpdate` を実行します。`-Update` は manifest を書き換えるため、検証では bucket 本体へ向けません。取得先への通信とキャッシュ書き込みも発生します。
4. 生成差分を読み、各 architecture が使う URL、hash、展開先を照合します。バイト単位の一致は現在版で差分がない証拠です。将来の版の置換や展開が正しい証拠にはしません。
5. 配布アーカイブの一覧と展開結果で `extract_dir` および必要な実行ファイルを確認します。検証した変更を正本へ反映し、対象外の差分がないことを確認します。

## 差分を判断する条件

| 確認点 | 判断 |
|---|---|
| 変数置換 | `substitute` は文字列置換です。標準キーは `$version` であり `${version}` ではありません。`$cleanVersion_64bit` のような接尾辞も、キーと残りの文字列として扱います |
| 値とテンプレートの配置 | `hash` 以外の通常プロパティは、値とテンプレートが共に top-level ならそこで更新します。それ以外は architecture ごとの値を探し、テンプレートを arch 側、top-level の順に探します |
| 更新されない値 | 値だけ top-level、テンプレートだけ arch 側の組み合わせを調べます。両方に値があると、更新された top-level より arch 側の古い値がインストールで優先される場合があります。`hash` は別分岐なので個別に確認します |
| 空の展開結果 | 存在しない `extract_dir` の指定では、7-Zip が 0 件のまま成功終了する場合があります。終了コードだけで展開成功としません |
| hash の取得 | 公開 checksum の利用有無とダウンロードによる計算への fallback を確認します。取得したバイトからの計算は、それが正規資材である証明にはなりません。配布元と通信経路も確認します |

置換と配置は [core.ps1](https://github.com/ScoopInstaller/Scoop/blob/master/lib/core.ps1) と [autoupdate.ps1](https://github.com/ScoopInstaller/Scoop/blob/master/lib/autoupdate.ps1) を参照します。将来の実装差は対象環境の版を優先します。

## release 直後の hash 不一致

manifest の更新時刻と資材の公開完了を照合します。配布元の asset ID、size、state、digest、取得結果と、CI / Excavator のログを使います。`created_at` と `updated_at` の近さだけでは、差し替えやアップロード未完了を確定できません。

version が既に最新なら、通常の自動更新では hash が再計算されない場合があります。配布資材が完成したことを確認してから一時コピーで `-ForceUpdate` を実行し、生成された hash と実物を照合します。既存の不一致 hash を根拠なく手書きで置き換えません。
