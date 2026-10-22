# VM の作成と OS 導入

## 方式と版

VirtualBox CLI が既存ホストで利用可能か、必要な host driver/仮想化機能が揃っているか
読み取ります。CLI の通常操作が非昇格でも、製品導入や host 変更まで不要とは限りません。
Windows Sandbox に必要な Store/App Installer/再起動機能があるかは対象版で確認します。

実行版の `VBoxManage --version` と `VBoxManage help <command>` で構文を確認します。
公式 Windows ISO の edition と掲載 SHA-256 を照合し、OS の CPU/メモリ/EFI/TPM/
Secure Boot 条件に対応する VM を選びます。過去の ISO の image index をコピーしません。
[VirtualBox 7.2 ユーザーガイド](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/index.html)

## 構成の確認点

- unattended helper の媒体と OS disk の controller/port を区別します。
  setup が disk を見つけない場合は controller と driver を確認します。
- NVRAM store の存在と key の状態を確認してから Secure Boot を操作します。
  Oracle PK/Microsoft signatures の登録と enable は別の操作です。既存 store の再初期化を
  原因不明の再試行に使いません。
- Windows ゲストの時刻は host/guest の期待する RTC と timezone を確認します。
  存在しない option や Linux 向けの UTC 前提を流用しません。
- host の Hyper-V/VBS と VirtualBox の NEM fallback はログで確認します。
  過去に有効だった paravirtualization/vCPU の回避値を、作成時の必須条件にしません。
  インストール時の CPU 要件と、壊れた既存 guest の起動回避は別に判断します。

## 無人導入

`unattended detect` で対象 ISO を確認し、locale、timezone、account、edition、Guest Additions
の要否を最初に決めます。認証値は必要最小限の保護された入力で渡し、command line や
生成 answer file を含むログへ残さないよう確認します。

Guest Additions が補助媒体に同梱される構成では、専用 ISO が別接続されないだけで
失敗としません。導入後に実サービスと guestcontrol で確認します。
setup/post-install の途中で controller や CPU を変更すると後続処理が変わるため、
介入前に状態を保存して再開経路を確認します。

詳細構文は実行版の [VBoxManage command reference](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/vboxmanage.html)
の `unattended`、`modifynvram`、`modifyvm` を読みます。
