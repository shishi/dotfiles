# Synology Photos → Immich 移行ツール設計書

## 概要

Synology Photos から Immich へ写真・動画を移行するための Python ツール。
メタデータ（EXIF、GPS、アルバム）を保持しつつ、安全に大規模データを移行する。

## 要件

### 必須要件
- EXIF（撮影日時）の移行
- GPS 位置情報の移行
- アルバム構造の移行
- アルバムに入っていない写真も全て移行

### Nice to Have
- お気に入り/評価
- 顔認識タグ
- 手動タグ/説明文
- 共有設定

### 対応形式
- JPEG, PNG, HEIF, 動画, Live Photos
- **全ファイル対象**（拡張子でフィルタリングしない）

### 規模
- 10,000〜50,000枚以上

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│                    synology_to_immich                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │  Synology   │    │   メイン    │    │   Immich    │     │
│  │  Reader     │───▶│  Migrator   │───▶│   Client    │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│        │                   │                   │            │
│        ▼                   ▼                   ▼            │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │ PostgreSQL  │    │  Progress   │    │  Immich     │     │
│  │ (アルバム)  │    │  Tracker    │    │  API        │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│        │                   │                                │
│        ▼                   ▼                                │
│  ┌─────────────┐    ┌─────────────┐                        │
│  │ SMB/FS      │    │ SQLite      │                        │
│  │ (実ファイル)│    │ (進捗DB)    │                        │
│  └─────────────┘    └─────────────┘                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### コンポーネント

| コンポーネント | 役割 |
|--------------|------|
| **Synology Reader** | PostgreSQL からアルバム・メタデータ取得、SMB/ローカルからファイル読み取り |
| **Migrator** | メインロジック。dry-run、バッチ処理、Live Photos ペアリング |
| **Immich Client** | Immich API を叩いてアップロード・アルバム作成 |
| **Progress Tracker** | 移行済みファイルを SQLite で記録（増分移行用） |

## データフロー

### 移行対象ファイルの取得

1. SMB/ローカルから全ファイルをスキャン（`/homes/shishi/Photo` 以下）
2. PostgreSQL からアルバム情報を取得（アルバム名 ↔ ファイルパスのマッピング）
3. マージして移行リスト作成
   - アルバムに入ってる写真 → アルバム情報付き
   - アルバムに入ってない写真 → アルバムなしでそのまま移行

### 除外パターン

```python
EXCLUDE_PATTERNS = [
    "@eaDir",      # Synology メタデータフォルダ
    ".DS_Store",   # macOS
    "Thumbs.db",   # Windows
    ".thumbnail",  # サムネイルフォルダ
]
```

### Live Photos の処理

Live Photos は「写真 + 動画」のペア（例：`IMG_1234.HEIC` + `IMG_1234.MOV`）

1. 同じベース名のファイルをグループ化
2. Immich API で Live Photo として一緒にアップロード
   - `assetData`（写真）+ `livePhotoData`（動画）を同時に送信
3. **ZIP化は絶対しない**

### タイムスタンプの処理

**優先順位：**
1. Synology Photos PostgreSQL のメタデータ（最優先）
2. EXIF の DateTimeOriginal
3. ファイルの更新日時（フォールバック）

**重要な原則：**
- タイムゾーンを勝手に付与しない
- 元のデータをそのまま保持（タイムゾーン情報があればそのまま、なければないまま）

## エラーハンドリングとログ

### ログ出力先

```
logs/
├── migration_YYYYMMDD_HHMMSS.log    （全ログ）
├── errors_YYYYMMDD_HHMMSS.log       （エラーのみ）
└── unsupported_YYYYMMDD_HHMMSS.log  （未対応形式専用）
```

### エラー分類

| エラー種別 | 処理 |
|-----------|------|
| **Unsupported Format** | 専用ログに記録、続行 |
| ネットワークエラー | リトライ（3回）、失敗なら記録 |
| ファイル読み取り不可 | 記録して続行 |
| API エラー | 記録して続行 |

### Unsupported Format 専用ログ

```
============================================================
⚠️  UNSUPPORTED FORMAT DETECTED
============================================================
File: /homes/shishi/Photo/2024/vacation/IMG_0001.xyz
Size: 2.4 MB
Attempted MIME: application/octet-stream
Immich Response: "Unsupported file format"
Timestamp: 2025-01-31 14:30:22
============================================================
```

### 最終レポート

```
============================================================
📊 MIGRATION REPORT
============================================================
Source files found:     45,230
Excluded (@eaDir etc):   1,204
Eligible for migration: 44,026
------------------------------------------------------------
✅ Successfully migrated: 43,890
⚠️  Unsupported format:      98
❌ Failed (other errors):     38
------------------------------------------------------------
Albums created:            156
Albums with items:         152
------------------------------------------------------------
Duration: 3h 24m 15s
============================================================
```

## 進捗管理と増分移行

### 進捗データベース（SQLite）

```sql
CREATE TABLE migrated_files (
    id INTEGER PRIMARY KEY,
    source_path TEXT UNIQUE NOT NULL,
    source_hash TEXT,
    source_size INTEGER,
    source_mtime TEXT,
    immich_asset_id TEXT,
    migrated_at TEXT,
    status TEXT  -- 'success' / 'failed' / 'unsupported'
);

CREATE TABLE migrated_albums (
    id INTEGER PRIMARY KEY,
    synology_album_id INTEGER,
    synology_album_name TEXT,
    immich_album_id TEXT,
    created_at TEXT
);

CREATE INDEX idx_source_path ON migrated_files(source_path);
CREATE INDEX idx_status ON migrated_files(status);
```

### 増分移行フロー

1. ソースの全ファイルリスト取得
2. 進捗DBと照合
3. 未移行 or 変更ありのファイルを特定
   - 新規ファイル → 移行対象
   - ハッシュ変更 → 再移行対象
   - 移行済み＆変更なし → スキップ
4. 対象ファイルのみ処理

### 中断・再開

- 進捗DBに記録済みのファイルはスキップ
- 自動的に前回の続きから再開

## CLI コマンド

### 基本構造

```bash
python -m synology_to_immich <command> [options]
```

### コマンド一覧

| コマンド | 説明 |
|---------|------|
| `migrate` | メイン移行処理 |
| `verify` | 整合性検証（NAS/DB/Immich 3ソース比較） |
| `status` | 現在の移行状況表示 |
| `retry` | 失敗したファイルの再試行 |
| `albums` | アルバム一覧・状態表示 |

### migrate コマンド

```bash
python -m synology_to_immich migrate \
  --source "smb://100.71.227.37/homes/shishi/Photo" \
  --smb-user "shishi" \
  --smb-password-prompt \
  --synology-db-host 100.71.227.37 \
  --synology-db-port 5432 \
  --immich-url http://100.71.227.37:2283 \
  --immich-api-key YOUR_API_KEY \
  --dry-run \
  --batch-size 100 \
  --batch-delay 1.0
```

### verify コマンド（整合性検証）

```bash
python -m synology_to_immich verify \
  --source "smb://100.71.227.37/homes/shishi/Photo" \
  --smb-user "shishi" \
  --immich-url http://100.71.227.37:2283 \
  --immich-api-key YOUR_API_KEY \
  --output verify_report.json
```

**検証内容（3-way verification）：**

| チェック項目 | 説明 |
|-------------|------|
| NAS only | DBにもImmichにもない（未移行） |
| DB only | DBにはあるがImmichにない（欠損） |
| Immich only | ImmichにあるがDBにない（手動アップ?） |
| Hash mismatch | 移行後にファイルが変更された |

### SMB オプション

| オプション | 説明 |
|-----------|------|
| `--source` | SMB URL またはローカルパス |
| `--smb-user` | SMB ユーザー名 |
| `--smb-password-prompt` | パスワードを対話入力 |
| `--smb-password-env` | 環境変数名を指定 |

## 安全機能

- **dry-run モード**: 実行せずシミュレーション
- **増分移行**: 未移行のものだけ処理
- **バッチサイズ指定**: 小分けで処理
- **移行ログ/レポート**: 全操作を記録
- **整合性検証**: NAS/DB/Immich の3ソース比較

## 技術スタック

- **言語**: Python（コメント多め、初心者向け）
- **開発環境**: flake.nix
- **SMB**: smbprotocol
- **進捗DB**: SQLite
- **Synology Photos DB**: PostgreSQL（読み取りのみ）
- **Immich**: REST API

## 環境情報

- NAS 写真実体: `smb://100.71.227.37/homes/shishi/Photo`
- Synology Photos: `100.71.227.37:62081`
- Immich: `100.71.227.37:2283`

## 参考リソース

- [Synology Photos PostgreSQL スキーマドキュメント](https://github.com/hubmartin/synology-photos-postgres-docs)
- [Immich API ドキュメント](https://api.immich.app/endpoints/albums)
- [Immich CLI](https://docs.immich.app/features/command-line-interface/)
- [immich-go](https://pkg.go.dev/github.com/simulot/immich-go)

## 注意事項

- 顔認識データは完全移行が難しい（Immich は埋め込みベクトルが必要）
- 既存ツール（PhotoMigrator等）の問題点：
  - タイムスタンプの勝手なタイムゾーン付与
  - Live Photos の ZIP 化
- これらの問題を本ツールでは回避する
