---
name: writing-rspec
description: RSpec のテストを新規作成・修正・レビューするときに使う。spec の共通化や let の配置を検討するときも対象。
---

# 読み下せる RSpec

テストで最も大事なのは、各 example を上から読み下せることです。
離れた宣言を頭に保持しなくても、準備・実行・期待結果がその場で分かるように書きます。
短さや重複の削減より、この読みやすさを優先します。

## 書き方

- 基本形は `describe` / `it` と、対象を明示した `expect` です。
  `context` は条件の整理に使い、宣言を上書きするためだけに階層を増やしません。
- `it` には検証する振る舞いを説明する名前を書きます。
  `subject` や `it { is_expected... }` を標準形にせず、操作と検証対象を本文に書きます。
- データとテスト対象は、まず `it` 内のローカル変数で表します。
  準備、対象の操作、`expect` を読む順に並べます。
- `let` / `let!` は必要最低限にします。ローカル変数で読みやすく書けるなら使いません。
  残す場合は利用する example の近くに置きます。
  親 context の宣言や、別の `let` への依存、子 context での上書きを追わせないようにします。
- `shared_examples` / `shared_examples_for` / `shared_context` と、それらを利用する
  `it_behaves_like` / `it_should_behave_like` / `include_examples` / `include_context` は使いません。
  メタデータによる共有 context の自動適用など、別の方法で同じ共有を持ち込むこともしません。
- 同じ準備や期待値は、必要なだけ何度でも書いて構いません。
  重複しているという理由だけで共通化しません。
- `let` を減らすために、example 固有の前提や操作を `before`、`subject`、独自ヘルパーへ
  移して隠しません。共通の環境準備とは区別し、テストの意味を決める値や操作は近くに置きます。

## 追加の機能を選ぶとき

使える機能を増やすこと自体を目的にせず、具体的な利点がある場合に限って使います。
shared 系を使わない方針は、この判断による例外を設けません。

- `before` は example ごとの共通の環境準備に必要な場合に使います。
  `before(:all)` / `before(:context)` でテストデータや可変状態を使い回しません。
  example ごとの初期化・後片付けの外に状態を置くと、テスト同士が干渉するためです。
- `allow_any_instance_of` / `expect_any_instance_of` に頼らず、対象のインスタンスを明示します。
  内部の依存関係を一括で置き換えて隠すより、どの相手とのやり取りを検証するか示します。
- 同じ操作の結果を複数の観点で確認する場合は、同じ example に期待結果を並べて構いません。
  複数の失敗をまとめて知りたいときは `aggregate_failures` を検討します。
  別々の振る舞いを、準備の使い回しだけを目的に一つの example へ詰め込みません。

## 例

配列の準備が重複しても、それぞれの example 内で前提と結果を確認できます。

```ruby
RSpec.describe Array, "#delete" do
  it "一致する要素を取り除く" do
    items = ["apple", "banana", "apple"]

    items.delete("apple")

    expect(items).to eq(["banana"])
  end

  it "一致する要素がなければ内容を変えない" do
    items = ["apple", "banana", "apple"]

    items.delete("orange")

    expect(items).to eq(["apple", "banana", "apple"])
  end
end
```

## 既存 spec を直すとき

依頼された範囲で、共有された準備や期待値を各 example に展開します。
`let!` やフックを移すときは、データ作成・副作用・対象操作の実行順を確認します。
検証していた条件と期待結果を維持し、変更した spec を実行します。
無関係な spec まで一括で書き換えません。

見直すときは、各 example の前提・操作・期待結果をその場で説明できるか確認します。
離れた `let` や共有定義を記憶しないと読めない箇所は、その場に戻します。

## 参考

[【翻訳】RSpecのリードメンテナだけど何か質問ある？](https://qiita.com/jnchito/items/3a8d19fd9a30468cafd4)
のシンプルな記述を優先する考え方を参考にしています。必要な判断基準は本文に含めています。
shared 系の禁止は、この記事の主張ではなく本スキルの方針です。
