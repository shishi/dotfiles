---
name: windows-gpu-diagnostics
description: Windows の GPU 負荷・VRAM 使用量・高クロック・電力・P-state の原因を調べるときに使います。GPU 設定変更やドライバー導入そのものの手順ではありません。
---

# Windows GPU の読み取り調査

GPU 全体とプロセス別の観測を同じ時間帯で照合し、観測値、原因候補、確定した原因を分けて報告します。診断の依頼だけでプロセスやサービスの停止、設定変更、再起動、ドライバー導入を行いません。

## 負荷とメモリを採取する

OS、GPU、ドライバーの種類と版、表示アダプター数を確認します。英語名のカウンターが見つからない場合は `Get-Counter -ListSet *` で利用可能な名前を確認します。取得失敗を 0 と扱いません。

```powershell
$gpuLoad = (Get-Counter '\GPU Engine(*)\Utilization Percentage' -SampleInterval 1 -MaxSamples 10).CounterSamples
$gpuMemory = (Get-Counter '\GPU Process Memory(*)\Local Usage' -MaxSamples 1).CounterSamples
$gpuLoad | Select-Object Timestamp, InstanceName, CookedValue, Status
$gpuMemory | Select-Object Timestamp, InstanceName, CookedValue, Status
```

- インスタンス名の PID、LUID、phys、eng、engtype を保持します。LUID はアダプターの相関に使い、異なるアダプターや時刻の値を PID だけで合算しません。
- `3d` に加え `copy`、`videodecode`、`videoencode`、`compute_*` など実際にある engine を確認します。各 engine の率を単純加算して GPU 全体の使用率にしません。
- VRAM は同時刻・同一アダプターで比較します。プロセス間の共有領域や計測範囲の違いがあるため、プロセス使用量の合計と GPU 全体が一致するとは限りません。[Windows の GPU 計測](https://devblogs.microsoft.com/directx/gpus-in-the-task-manager/)

## NVIDIA の場合

NVIDIA GPU と `nvidia-smi` の存在を確認してから実行します。非対応の項目は不明として残します。

```powershell
nvidia-smi --query-gpu=index,name,driver_version,memory.used,power.draw,pstate,clocks.sm,clocks.max.sm,clocks.mem,clocks.max.mem,utilization.gpu --format=csv
```

同じ GPU の `memory.used` とカウンターを照合します。P-state、電力、クロック、使用率は別の指標です。0% はその標本期間の値であり、CUDA コンテキスト保持者や高電力の原因を確定しません。

| 観測 | 次に確認するもの |
|---|---|
| 0% でも P2・高クロックが続く | compute を使うプロセス、電力管理設定、複数標本での推移 |
| 高クロックが持続する | アプリごとの電力管理設定、実負荷、表示構成、ドライバーの状態 |
| マルチモニターでメモリクロックが高い | 解像度・リフレッシュレートと GPU の対応。表示構成だけで他の原因を除外しない |

WDDM ではプロセス情報に制約があります。`--query-compute-apps` の列挙だけで graphics と compute を区別して CUDA 保持者を決めません。利用中のドライバーが返す process type と、engine の観測を確認します。プロセス別 GPU メモリが取得不能になる制限もあります。[nvidia-smi の仕様](https://docs.nvidia.com/deploy/nvidia-smi/)

## プロセスの確認

`Get-CimInstance Win32_Process` の `ProcessId`、`ParentProcessId`、`CreationDate` を照合します。PID は再利用されるので、子より新しい生成時刻のプロセスを親と見なしません。[Win32_Process の仕様](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-process)

必要なら候補プロセスの `Modules` から `nvcuda*.dll` の読み込みを調べます。DLL の存在は実行中の compute 負荷の証明ではありません。昇格・保護プロセス、終了済みプロセスなど取得できない対象と理由も記録します。`ExecutablePath` の空値だけで保護プロセスと断定せず、`tasklist /v` など取得可能な名前と PID で補います。

HAGS が仮説に関係する場合は現在値と UI の状態を読む範囲に留めます。設定変更や昇格を要する調査が必要なら、その操作が依頼に含まれるかを確認してから進めます。観測だけで原因を確定できない場合は、残った候補とそれを区別する最小の観測を示します。
