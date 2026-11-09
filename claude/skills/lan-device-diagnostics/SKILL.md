---
name: lan-device-diagnostics
description: LAN の機器が見つからない、DHCP・一時 IP・有線リンク速度を調べる場合に使います。Tailscale の経路競合は tailscale-lan-diagnostics を使います。
---

# LAN 機器と接続状態の診断

機器の管理 IP、L2 の転送、DHCP、物理リンクを分けて調べます。個人環境の構成は関連記憶と設定の正本から取得します。

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
- 改善は同じ宛先・方向・データ量で測ります。接続成功やリンク表示だけで実転送の改善としません。VPN の経路が選ばれている場合は `tailscale-lan-diagnostics` へ進みます。

構文と副作用は [New-NetIPAddress](https://learn.microsoft.com/en-us/powershell/module/nettcpip/new-netipaddress)、[Set-NetIPInterface](https://learn.microsoft.com/en-us/powershell/module/nettcpip/set-netipinterface)、[Get-NetAdapter](https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapter) を実行版と照合します。
