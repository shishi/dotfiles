# 観測と復旧

## 無反応を分類する

画面、VM state、disk I/O、guest/host CPU、VBox.log の更新を同じ時点で取得します。
`.vdi` の増分 0 だけでは要件 dialog 待ち、idle、deadlock を区別できません。
guest のアプリや VBoxService の監視自体が CPU を占有していないかも確認します。
細かすぎる polling で小さな guest の資源を消費しません。

撮影エラーの場合は log の display resize/bpp/fallback buffer を確認します。
画面消灯が疑われるなら害のない入力で起こし、再撮影します。撮影不能を OS 停止と
同一視しません。黒画面も disk I/O や setup の進行と照合します。

NEM 下の spin が疑われる場合は、実行版の `debugvm getregisters` 等で複数 vCPU の
命令位置を時間をあけて比較できます。同じ位置でも idle loop の場合があるため、
host CPU 消費と対比します。画面と進捗の別証拠なしに deadlock と断定しません。

## 介入する

guest の reset/poweroff は未保存の状態や post-install を失い得ます。
対象 UUID、現在の処理、影響と再開方法を確認し、承認範囲内で最小の介入を選びます。
reset 後に setup が進んでも、Guest Additions 等の後処理が完了したか再確認します。
VM が応答しないというだけで VBoxSVC や他の稼働 VM を一括停止しません。

ACPI power button は guest の policy によって sleep になる場合があります。
guest 内の通常 shutdown を使い、最後に `showvminfo` 等で poweroff を確認します。
screen off、sleep、running、poweroff を分けて記録します。

結果回収後は、今回作成した VM と媒体を所有一覧で照合します。共有 ISO、既存 VM、
未回収ログを巻き込まず、credential を含む answer file も保持/撤去の対象に含めます。
状態取得と操作の構文は [VBoxManage の公式参照](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/vboxmanage.html)
を実行版の help と照合します。
