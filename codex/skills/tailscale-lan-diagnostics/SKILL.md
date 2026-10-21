---
name: tailscale-lan-diagnostics
description: LAN 内の通信が Tailscale を通る、NAS/SMB が遅い、subnet route の広告と実経路が一致しない場合に診断します。通常のアプリ公開や ACL 設計だけでは使いません。
---

# Tailscale と LAN の経路診断

宛先の見た目ではなく、選択された route・送信元・NIC の転送量から実経路を確かめます。
個人環境の構成と変更の正本はプロジェクト記憶・repo から取得します。
repo 経由の変更が必要な環境で、端末へ直接設定を反映しません。

## 切り分け

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
   `tailscale status --json` の情報と OS の実経路を対比し、広告設定だけで配布済みとしません。
4. SMB では接続と選択チャネルを確認し、同じ負荷で NIC 統計の前後差分を取ります。
   Windows の `Get-SmbMultichannelConnection` は実行権限を確認します。
   `Get-NetAdapterStatistics` は実行版の引数を調べ、NIC 名を指定します。
   チャネルが負荷時に追加されることもあるため、アイドル時の数だけで異常としません。

## 修正の判断と確認

- LAN 直結端末で subnet route を受け取る必要がなければ、受信停止を候補にします。
  遠隔拠点への接続を必要とする端末では、その機能を失わない方法を比較します。
  `accept-routes` の変更と router 側の広告・承認の変更は別の操作です。
- metric や route を変える場合は、ケーブル抜去・拠点外への移動時の経路も確認します。
  固定 route が残って到達不能になる対処を、速度改善だけで採用しません。
- LAN prefix 変更時は router の広告と承認・配布を再確認します。
  拠点間で同じ IPv4 範囲が重なる問題と、LAN 直結 route の優先順位の問題を分けます。
  重複範囲には再採番や 4via6 を比較し、IPv6 宛先を使えるアプリかも確認します。
- 承認済みの変更を構成の正本へ反映し、同じ宛先の送信元・NIC 転送量と転送結果を再取得します。
  同じファイルサイズ・方向・負荷で速度を比較し、再接続成功だけで完了しません。

仕様は [LAN 接続の問題](https://tailscale.com/docs/reference/troubleshooting/connectivity/connect-lan-failure)
と [OS 別の経路優先](https://tailscale.com/docs/reference/troubleshooting/network-configuration/lan-traffic-overlapping-subnets)、
[4via6](https://tailscale.com/docs/features/subnet-routers/4via6-subnets) を参照します。
