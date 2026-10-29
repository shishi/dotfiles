# 広告配信を判定するときの参照先

以下は配信の役割を調べるための知見です。遮断リストではありません。採用時は現在の配布物、対象端末の通信、通常機能への影響を照合します。SDK や公開ページで確認した用途を、対象端末でその広告が表示された証拠に置き換えません。

## Moloco：素材、クリック遷移、キャッシュ

参照元は [公式 iOS 配布定義](https://github.com/moloco/moloco-sdk-ios-spm/blob/main/Package.swift)、[Android SDK 配布元](https://repo.maven.apache.org/maven2/com/moloco/sdk/moloco-sdk/)、[Android SDK 文書](https://moloco.github.io/android-sdk-docs/index.html) です。

- Android SDK 4.14.0 の `LegacyMediaDownloader` と `ChunkedMediaDownloaderImpl` は、渡された素材 URL を GET します。確認した再試行では同じ URL を使います。Range 非対応時の全体取得への切り替えは、別 CDN への切り替えではありません。
- 同版の NativeAd モデルにある `url`・`clickTrackerUrls`・`fallbackUrl` はクリック遷移の組です。`fallbackUrl` という名前だけで素材配信の予備ホストに分類しません。
- Android の `MediaCacheRepository` は保存済み素材を返す経路を持ちます。iOS SDK 4.12.0 には `SSRAssetCache` と WebKit の `molocoasset` 用ハンドラーがあります。キャッシュ機構の存在だけでは、広告が残った原因をキャッシュと断定できません。
- 調べた Android HTTP クライアントと依存する Ktor Android 3.2.3 の実装では、独自 DNS・直 IP・別 CDN への切り替えを確認していません。動的に渡される URL や別バージョンまで否定する根拠にはなりません。
- 公式 SDK 配布物にある `https://cdn-f.adsmoloco.com/moloco-cdn/privacy.html` と `advertising-policy.html` はプライバシー・広告方針の参照です。この固定文字列から、残った広告素材の URL は特定できません。

配布物のバージョンとハッシュを残し、素材ローダー、クリック処理、キャッシュ、実ログを別々に対応づけます。広告の遷移先を素材配信先と取り違えて遮断対象を増やしません。

## Pangle・TikTok：実際のパスと共有ホスト

- [TikTok の Pangle playable 導入資料](https://ads.tiktok.com/resources/help/article/how-to-create-tiktok-pangle-playable-ads) に対応する配信物として、`https://sf16-muse-va.ibytedtos.com/obj/union-fe-nc-i18n/playable/sdk/playable-sdk.js` を確認しています。パスは小文字です。古い資料の別表記で 404 が返っても、このホストの用途を否定できません。
- [TikTok 広告ライブラリの確認例](https://library.tiktok.com/ads/detail/?ad_id=1873863495056546) のポスターに `p16-common-sign.tiktokcdn.com` の画像参照を確認しています。同じホストは通常画像も扱いうるため、ホスト全体の遮断では通常の TikTok 画像も失う可能性があります。広告詳細ページは消える場合があるので、再調査では公開中の広告から参照を辿ります。期限付き署名 URL は恒久的な検査入力にしません。

## Google：動画広告とアプリ内キャンペーン

- [IMA HTML5 導入資料](https://developers.google.com/interactive-media-ads/docs/sdks/html5/client-side/get-started) の SDK は `https://imasdk.googleapis.com/js/sdkloader/ima3.js` です。同じホストの `ima3_dai.js` は動画へ広告を組み込む DAI に使われます。ホスト全体の遮断では一部の動画再生も損なう可能性があります。
- [Firebase iOS のキャンペーン取得実装](https://github.com/firebase/firebase-ios-sdk/blob/main/FirebaseInAppMessaging/Sources/Flows/FIRIAMMsgFetcherUsingRestful.m) は `firebaseinappmessaging.googleapis.com` の `eligibleCampaigns:fetch` を使います。[応答パーサー](https://github.com/firebase/firebase-ios-sdk/blob/main/FirebaseInAppMessaging/Sources/Data/FIRIAMFetchResponseParser.m) はバナー・モーダル・画像・カードと画像 URL を扱います。これはアプリ内キャンペーン配信であり、有料の AdMob 広告と同一視しません。保存済みメッセージや素材の表示も別に確認します。

## 広告復旧スクリプトと同一ホストの販促

- `html-load.com` のローダーには広告除去の検出と広告復旧の処理があります。[AdGuard の保守者による調査](https://github.com/AdguardTeam/AdguardFilters/issues/214968) では DNS 遮断によるページ破損も扱っています。ホストを止めた事実だけで、記事を保って広告を除去できたとは扱いません。対象ページの素材 URL と本文の表示を照合します。
- 出版社自身の販促画像は記事と同じホストから配信される場合があります。例えば `ryukyushimpo.jp/uploads/` と画像変換用の `/tachyon/` は同一ホストです。特定バナーの URL と表示要素を確認し、サイト全体の DNS 遮断で代用しません。

## アプリ配布物を根拠にするとき

第三者ミラーから得た APK は、配布ページの表示だけで公式の実装として扱いません。署名を検証し、公式サイトの `/.well-known/assetlinks.json` などの証明書指紋と照合します。DEX の文字列から呼出元を探した結果は候補です。標準の逆アセンブラー等でメソッド、要求 URL・ヘッダー、応答処理、通常機能へのフォールバックを辿ります。Android 配布物の調査を、iOS 版の同一実装や画面の受入確認に置き換えません。

ジャンプ＋の Android 配布物（配布ページの表記は 4.0.41、APK の SHA-256 は `435d2ccd4bb61bd947228da8ef6736a56c4e7e8989d243677a934ba85f84124e`）では、[公式サイトの署名情報](https://shonenjumpplus.com/.well-known/assetlinks.json) と証明書を照合し、`https://splash-jack.shonenjumpplus.com/` への起動時 GET を確認しています。要求には `X-Giga-Platform: App Android` が付き、失敗・配信なしでは通常の起動時表示へ戻ります。ヘッダーなしの root が 400 でも実装の用途を否定できません。Android 実装の確認であり、iOS 側の表示原因は別途確認します。

## 素材配信と広告計測を区別する例

- [Prebid の zMaticoo 資料](https://docs.prebid.org/dev-docs/bidders/zmaticoo.html) と対応する `https://creative.cdnyeah.com/tpl/renderer/video/zmaticooOutsteam.js` は、動画広告の描画処理を調べる入口です。
- `disk.akamaized.net` の公開一覧から `/assets/` の広告 PNG と広告 HTML を確認しています。これは個別ホストの配信内容の根拠であり、`akamaized.net` 全体を広告専用とする根拠ではありません。HTML 内でも素材取得、表示計測、クリック遷移を分けます。
- [Yahoo の配信 JavaScript](https://s.yimg.jp/images/listing/tool/cv/ytag.js) の `yjad_retargeting` は `apm.yahoo.co.jp/rt` を取得し、応答の `X-Z-Burls` から追加の要求先を得ます。[公開通信記録](https://urlscan.io/result/01a07303-5fa3-72be-b476-07e473d593a4/) にある `dm.slim02.jp/tppa/v2/vs` は、この広告計測の関係を調べる根拠です。計測の遮断を素材の遮断と数えず、識別子入りの追跡 URL を検証のために再送しません。
