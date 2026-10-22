# ゲストとの入出力

## Guest Additions が動く場合

guestcontrol の入力ファイルを guest 側へ配置し、PowerShell は複雑な `-Command` を
何層も解釈させず `.ps1` の `-File` で実行します。copy の宛先は明示し、guest 内で
bytes/hash を照合します。実行版の `copyto/copyfrom/run/start` の help を確認します。

copyfrom が対象環境で失敗する場合は、配置済み script の stdout で結果を取得する等、
観測する内容を保った別経路へ切り替えます。一環境の失敗を製品全体の非対応としません。
guestcontrol session の終了で子 process が止まるか確認し、長時間 job は既存の
guest 内の job/task 管理へ渡して結果ファイルを回収できます。

## Guest Additions がない場合

- 入力は VISO/ISO に script と検証資材を載せられます。対応する VirtualBox の媒体構文を
  使い、対象 VM の optical drive だけを差し替えます。既存媒体が導入中でないか確認します。
- drive letter を固定とみなさず、batch 自身の drive 等から解決します。
- 回収は仮想 serial の file 接続等を使えます。既存の port と host 出力先を確認し、
  guest から短い既知の文字列を送って、ホストへ届くことを先に確認します。
- spinner 等の表示行を除去する場合は、未加工ログも保持し、結果行まで削っていないか照合します。
- 実行は対話 desktop の Run 等から始め、結果/終了状態を同じ媒体やログ経路で回収します。

## 対話入力と昇格

guestcontrol の desktop/token を、ログイン中ユーザーの対話環境と同じと仮定しません。
winget や UAC の表示が必要なら、実 desktop から起動する経路を用意します。

キーボード入力は locale 名から US/JIS を推測せず、害のない文字列で配列を確認します。
Run に渡した内容を Enter 前に画面で確認します。UAC の既定フォーカスが許可側とは
限らないため、本人の承認が必要な prompt を自動 key で許可しません。
隔離した使い捨て guest の無人昇格が明示的に承認された場合も、その範囲を host や他 VM の
UAC policy へ広げず、検証条件と元の設定を保持します。

認証には実行版が対応する password-file 等を使い、credential を command line、
スクリーンショット、回収ログへ露出させません。
操作の構文は [guestcontrol と controlvm の公式参照](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/vboxmanage.html)
で確認します。
