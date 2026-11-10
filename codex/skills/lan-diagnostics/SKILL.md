---
name: lan-diagnostics
description: LAN の機器が見つからない、DHCP・一時 IP・有線リンク速度を調べる、LAN 内の通信が遅い・Tailscale を通る、NAS/SMB が遅い、subnet route の広告と実経路が一致しない場合に診断します。通常のアプリ公開や ACL 設計だけでは使いません。
---

# LAN の機器と経路の診断

機器の管理 IP、L2 の転送、DHCP、物理リンク、Tailscale を含む実経路を分けて調べます。個人環境の構成と変更の正本は関連記憶・プロジェクト記憶・repo から取得します。

## 機器が見つからないとき

1. 調査対象の LAN 範囲、接続 NIC、IP/prefix、default gateway、DHCP サーバーを確認します。Windows は `ipconfig /all` と `Get-NetAdapter` を使えます。
2. 許可された範囲で ARP/neighbor table、対象管理ポートへの接続、対応機器の SSDP 応答を照合します。ICMP 無応答だけで機器の不在を判断しません。別 subnet の応答は送信元アドレスも記録します。
3. 管理 IP を持たないブリッジも L2 転送できます。探索で見つからないことだけを理由に初期化しません。機器の配線、MAC、DHCP lease、設定済みの管理 subnet から所在を絞ります。
4. 同一機器の複数 IP と NIC を対応づけます。同じ MAC の応答だけで別 NIC が無いと断定せず、機器設定や別の観測と照合します。

## 一時 IP と DHCP

Windows の `New-NetIPAddress` は、DHCP が有効な NIC にアドレスを追加すると DHCP を無効化します。別 subnet の管理画面へ到達するための一時操作でも、既存の lease と gateway を失う可能性があります。

変更が必要なら、対象 NIC と元の DHCP/IP/route を控え、管理接続を失った場合の復元経路を決めます。変更後だけでなく復元後も DHCP、lease、gateway、必要な宛先への通信を確認します。DHCP の再有効化には対象 NIC を指定した `Set-NetIPInterface -Dhcp Enabled` を使えます。一時アドレスや route の残存も別に照合します。

## 遅いとき

- 最初に実 NIC の `LinkSpeed` を確認します。想定外に 100 Mbps なら、両端の挿し込み、別ポート、ケーブルを比較し、毎回リンク速度を読み直します。
- 経路上のポートと末端 AP のポートを区別します。末端 AP の速度だけから、有線端末同士の転送上限を決めません。
- 改善は同じ宛先・方向・データ量で測ります。接続成功やリンク表示だけで実転送の改善としません。リンク速度に問題がなく、NAS/SMB など LAN 内の通信が遅い場合は、下の「Tailscale を通る経路」で実経路を確かめます。

## Tailscale を通る経路

宛先の見た目ではなく、選択された route・送信元・NIC の転送量から実経路を確かめます。
repo 経由の変更が必要な環境で、端末へ直接設定を反映しません。

1. 遅い通信の送受信端末、宛先 IP / 名前、LAN の prefix、物理リンク速度を確認します。
   サブネットが同一でも、実トラフィックが物理 NIC へ出るとは限りません。
2. Tailscale の受信 route、端末の `accept-routes`、OS の route と送信元を照合します。
   Windows では `Find-NetRoute -RemoteIPAddress "$DESTINATION"`、
   Linux では `ip route get "$DESTINATION"` などを使います。
   変数には実際の宛先を設定します。Windows では prefix 長を先に比較します。
   同じ長さなら interface metric と route metric の合計を確認します。
   Linux では `ip rule show` の優先規則と、その規則が参照する routing table を先に確認します。
   同じ table 内の prefix / metric 比較を、別 table を選ぶ policy routing と混同しません。
   どちらも最終的な `ip route get` や OS の選択経路と照合します。
3. subnet router の広告、管理側の承認、クライアントへの配布、実使用を分けます。
   `tailscale status` の health 行は広告中であることだけを示し、prefix を示しません。
   `tailscale status --json` の該当 peer の `PrimaryRoutes` で primary に選ばれた prefix を、
   `AllowedIPs` で承認・配布済みの prefix を確認します。exit node は `ExitNodeOption` も見ます。
   これらと OS の実経路を対比し、広告設定 (`AdvertiseRoutes`) だけで配布済みとしません。
4. SMB では接続と選択チャネルを確認し、同じ負荷で NIC 統計の前後差分を取ります。
   Windows の `Get-SmbMultichannelConnection` は実行権限を確認します。
   `Get-NetAdapterStatistics` は実行版の引数を調べ、NIC 名を指定します。
   チャネルが負荷時に追加されることもあるため、アイドル時の数だけで異常としません。

## Tailscale の経路を直すときの判断と確認

- LAN 直結端末で subnet route を受け取る必要がなければ、受信停止を候補にします。
  遠隔拠点への接続を必要とする端末では、その機能を失わない方法を比較します。
  `accept-routes` の変更と router 側の広告・承認の変更は別の操作です。
- metric や route を変える場合は、ケーブル抜去・拠点外への移動時の経路も確認します。
  固定 route が残って到達不能になる対処を、速度改善だけで採用しません。
- LAN prefix 変更時は router の広告が自動では追従しないため、広告と承認・配布を再確認します。
  `accept-routes` を無効にした LAN 直結端末では症状が出ず、外出先の端末だけが LAN に入れなくなります。
  `tailscale set --advertise-routes=<prefix>` は exit node の広告を保ったまま、subnet route の一覧を
  指定した値で置き換えます。残す prefix もすべて指定します。`tailscale up` で変更する場合は、
  既存の広告を含む既定でない設定をすべて再指定します。省略するとエラーで止まり、`--reset` を付けたときだけ
  省略した設定が既定へ戻ります。その後、管理側で新しい prefix を承認します。
- 拠点間で同じ IPv4 範囲が重なる問題と、LAN 直結 route の優先順位の問題を分けます。
  同じ prefix を複数の router が広告すると primary は 1 台だけになり、もう一方の拠点には届きません。
  拠点を追加するときは、家庭用ルーターの既定 (`192.168.0.0/24`・`192.168.1.0/24` 等) を避け、
  `10.<任意>.<任意>.0/24` のように他拠点と重なりにくい範囲を選びます。
  重複後の対処は、再採番、4via6、subnet router 上の iptables `NETMAP` の順に検討します。
  4via6 は宛先を IPv6 で書けるアプリでしか使えません。`NETMAP` は Tailscale の管理外で、自分で保守します。
- 承認済みの変更を構成の正本へ反映し、同じ宛先の送信元・NIC 転送量と転送結果を再取得します。
  同じファイルサイズ・方向・負荷で速度を比較し、再接続成功だけで完了しません。

構文と副作用は [New-NetIPAddress](https://learn.microsoft.com/en-us/powershell/module/nettcpip/new-netipaddress)、[Set-NetIPInterface](https://learn.microsoft.com/en-us/powershell/module/nettcpip/set-netipinterface)、[Get-NetAdapter](https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapter) を実行版と照合します。
仕様は [LAN 接続の問題](https://tailscale.com/docs/reference/troubleshooting/connectivity/connect-lan-failure)
と [OS 別の経路優先](https://tailscale.com/docs/reference/troubleshooting/network-configuration/lan-traffic-overlapping-subnets)、
[4via6](https://tailscale.com/docs/features/subnet-routers/4via6-subnets) を参照します。
