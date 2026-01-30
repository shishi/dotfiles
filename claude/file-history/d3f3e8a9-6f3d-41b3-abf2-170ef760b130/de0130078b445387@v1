# Synology to Immich Migration Tool - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Synology Photos から Immich へ写真・動画・アルバムを安全に移行する Python CLI ツールを TDD で実装する

**Architecture:** 4つの主要コンポーネント（SynologyReader, ImmichClient, ProgressTracker, Migrator）を順番に実装。各コンポーネントは独立してテスト可能。SMB/PostgreSQL からデータを読み、Immich API でアップロードし、SQLite で進捗を追跡する。

**Tech Stack:** Python 3.12, click (CLI), httpx (HTTP), smbprotocol (SMB), psycopg2 (PostgreSQL), SQLite, pytest

---

## Phase 1: プロジェクト構造とコア基盤

### Task 1: プロジェクト構造の作成

**Files:**
- Create: `src/synology_to_immich/__init__.py`
- Create: `src/synology_to_immich/__main__.py`
- Create: `src/synology_to_immich/config.py`
- Create: `tests/__init__.py`
- Create: `tests/conftest.py`
- Create: `pyproject.toml`

**Step 1: pyproject.toml を作成**

```toml
[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"

[project]
name = "synology-to-immich"
version = "0.1.0"
description = "Migrate photos from Synology Photos to Immich"
requires-python = ">=3.12"
dependencies = [
    "click>=8.0",
    "httpx>=0.25",
    "smbprotocol>=1.10",
    "psycopg2-binary>=2.9",
    "rich>=13.0",
    "tomli>=2.0",
    "pillow>=10.0",
    "exifread>=3.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.0",
    "pytest-cov>=4.0",
    "pytest-asyncio>=0.21",
    "black>=23.0",
    "ruff>=0.1",
    "mypy>=1.0",
]

[project.scripts]
synology-to-immich = "synology_to_immich.__main__:main"

[tool.setuptools.packages.find]
where = ["src"]

[tool.pytest.ini_options]
testpaths = ["tests"]
pythonpath = ["src"]

[tool.black]
line-length = 100

[tool.ruff]
line-length = 100
select = ["E", "F", "I"]
```

**Step 2: パッケージ初期化ファイルを作成**

`src/synology_to_immich/__init__.py`:
```python
"""
Synology Photos から Immich へ写真・動画を移行するツール

このツールは以下の機能を提供します:
- SMB 経由での NAS ファイルアクセス
- Synology Photos PostgreSQL からのアルバム情報取得
- Immich API へのアップロード
- 増分移行と進捗追跡
"""

__version__ = "0.1.0"
```

**Step 3: エントリーポイントを作成**

`src/synology_to_immich/__main__.py`:
```python
"""
メインエントリーポイント

python -m synology_to_immich で実行可能にする
"""

import click


@click.group()
@click.version_option()
def main():
    """Synology Photos から Immich へ写真・動画を移行するツール"""
    pass


# 後でサブコマンドを追加していく
# main.add_command(migrate)
# main.add_command(verify)
# main.add_command(status)


if __name__ == "__main__":
    main()
```

**Step 4: テスト設定を作成**

`tests/__init__.py`:
```python
"""テストパッケージ"""
```

`tests/conftest.py`:
```python
"""
pytest の共通フィクスチャ

テスト全体で使う共通の設定やモックをここに定義する
"""

import pytest
from pathlib import Path


@pytest.fixture
def tmp_workspace(tmp_path: Path) -> Path:
    """
    テスト用の一時ディレクトリを作成する

    各テストで独立したワークスペースを使える
    """
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    return workspace


@pytest.fixture
def sample_image_bytes() -> bytes:
    """
    テスト用の最小限の JPEG バイト列

    実際の画像ファイルを使わずにテストできる
    """
    # 最小限の有効な JPEG (1x1 pixel, gray)
    return bytes([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
        0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
        0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
        0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
        0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
        0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
        0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
        0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
        0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
        0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00, 0x02, 0x01, 0x03,
        0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D,
        0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06,
        0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
        0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72,
        0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45,
        0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
        0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75,
        0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
        0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3,
        0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
        0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9,
        0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
        0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4,
        0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01,
        0x00, 0x00, 0x3F, 0x00, 0xFB, 0xD5, 0xDB, 0x20, 0xA8, 0xA0, 0x02, 0x8A,
        0x00, 0xFF, 0xD9
    ])
```

**Step 5: テストが実行できることを確認**

Run: `cd /home/shishi/dev/src/github.com/shishi/synology_to_immich/.worktrees/feature-migration && nix develop -c pytest --collect-only`
Expected: "no tests ran" (まだテストがないので)

**Step 6: コミット**

```bash
git add -A
git commit -m "feat: initialize project structure with pyproject.toml and test setup"
```

---

### Task 2: 設定ファイル読み込み

**Files:**
- Create: `src/synology_to_immich/config.py`
- Create: `tests/test_config.py`

**Step 1: 設定クラスのテストを書く**

`tests/test_config.py`:
```python
"""
設定ファイル読み込みのテスト

config.toml からの設定読み込みと、コマンドライン引数のマージをテストする
"""

import pytest
from pathlib import Path
from synology_to_immich.config import Config, load_config


class TestConfig:
    """Config クラスのテスト"""

    def test_config_has_required_fields(self):
        """設定に必須フィールドが存在することを確認"""
        # Arrange & Act
        config = Config(
            source="smb://localhost/share",
            immich_url="http://localhost:2283",
            immich_api_key="test-key",
        )

        # Assert
        assert config.source == "smb://localhost/share"
        assert config.immich_url == "http://localhost:2283"
        assert config.immich_api_key == "test-key"

    def test_config_default_values(self):
        """デフォルト値が正しく設定されることを確認"""
        # Arrange & Act
        config = Config(
            source="/path/to/photos",
            immich_url="http://localhost:2283",
            immich_api_key="test-key",
        )

        # Assert
        assert config.dry_run is False
        assert config.batch_size == 100
        assert config.batch_delay == 1.0
        assert config.smb_user is None
        assert config.smb_password is None

    def test_config_detects_smb_source(self):
        """SMB URL を正しく検出できることを確認"""
        # Arrange
        smb_config = Config(
            source="smb://192.168.1.1/photos",
            immich_url="http://localhost:2283",
            immich_api_key="test-key",
        )
        local_config = Config(
            source="/mnt/photos",
            immich_url="http://localhost:2283",
            immich_api_key="test-key",
        )

        # Act & Assert
        assert smb_config.is_smb_source is True
        assert local_config.is_smb_source is False


class TestLoadConfig:
    """設定ファイル読み込みのテスト"""

    def test_load_config_from_toml(self, tmp_path: Path):
        """TOML ファイルから設定を読み込めることを確認"""
        # Arrange
        config_file = tmp_path / "config.toml"
        config_file.write_text("""
[source]
path = "smb://192.168.1.1/homes/user/Photo"
smb_user = "testuser"

[immich]
url = "http://localhost:2283"
api_key = "my-api-key"

[migration]
dry_run = true
batch_size = 50
""")

        # Act
        config = load_config(config_file)

        # Assert
        assert config.source == "smb://192.168.1.1/homes/user/Photo"
        assert config.smb_user == "testuser"
        assert config.immich_url == "http://localhost:2283"
        assert config.immich_api_key == "my-api-key"
        assert config.dry_run is True
        assert config.batch_size == 50

    def test_load_config_file_not_found(self, tmp_path: Path):
        """存在しない設定ファイルでエラーになることを確認"""
        # Arrange
        config_file = tmp_path / "nonexistent.toml"

        # Act & Assert
        with pytest.raises(FileNotFoundError):
            load_config(config_file)
```

**Step 2: テストを実行して失敗を確認**

Run: `cd /home/shishi/dev/src/github.com/shishi/synology_to_immich/.worktrees/feature-migration && nix develop -c pytest tests/test_config.py -v`
Expected: FAIL with "cannot import name 'Config' from 'synology_to_immich.config'"

**Step 3: Config クラスを実装**

`src/synology_to_immich/config.py`:
```python
"""
設定管理モジュール

設定ファイル（TOML）の読み込みと、コマンドライン引数のマージを行う。
設定の優先順位:
1. コマンドライン引数（最優先）
2. 設定ファイル（config.toml）
3. デフォルト値
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import tomli


@dataclass
class Config:
    """
    アプリケーション設定を保持するクラス

    Attributes:
        source: 移行元のパス（SMB URL またはローカルパス）
        immich_url: Immich サーバーの URL
        immich_api_key: Immich API キー
        dry_run: True の場合、実際にはアップロードしない
        batch_size: 一度に処理するファイル数
        batch_delay: バッチ間の待機秒数
        smb_user: SMB 接続用ユーザー名
        smb_password: SMB 接続用パスワード
        synology_db_host: Synology PostgreSQL ホスト
        synology_db_port: Synology PostgreSQL ポート
        synology_db_user: Synology PostgreSQL ユーザー
        synology_db_password: Synology PostgreSQL パスワード
        progress_db_path: 進捗データベースのパス
    """

    # 必須設定
    source: str
    immich_url: str
    immich_api_key: str

    # オプション設定（デフォルト値あり）
    dry_run: bool = False
    batch_size: int = 100
    batch_delay: float = 1.0

    # SMB 設定
    smb_user: Optional[str] = None
    smb_password: Optional[str] = None

    # Synology DB 設定
    synology_db_host: Optional[str] = None
    synology_db_port: int = 5432
    synology_db_user: Optional[str] = None
    synology_db_password: Optional[str] = None
    synology_db_name: str = "synofoto"

    # 進捗DB 設定
    progress_db_path: Path = field(default_factory=lambda: Path("migration_progress.db"))

    @property
    def is_smb_source(self) -> bool:
        """
        ソースが SMB URL かどうかを判定する

        Returns:
            True: SMB URL の場合
            False: ローカルパスの場合
        """
        return self.source.startswith("smb://")


def load_config(config_path: Path) -> Config:
    """
    TOML ファイルから設定を読み込む

    Args:
        config_path: 設定ファイルのパス

    Returns:
        Config: 読み込んだ設定

    Raises:
        FileNotFoundError: 設定ファイルが存在しない場合
    """
    if not config_path.exists():
        raise FileNotFoundError(f"設定ファイルが見つかりません: {config_path}")

    # TOML ファイルを読み込む
    with open(config_path, "rb") as f:
        data = tomli.load(f)

    # セクションごとにデータを取り出す
    source_section = data.get("source", {})
    immich_section = data.get("immich", {})
    migration_section = data.get("migration", {})
    synology_section = data.get("synology", {})

    # Config オブジェクトを作成
    return Config(
        # 必須設定
        source=source_section.get("path", ""),
        immich_url=immich_section.get("url", ""),
        immich_api_key=immich_section.get("api_key", ""),

        # オプション設定
        dry_run=migration_section.get("dry_run", False),
        batch_size=migration_section.get("batch_size", 100),
        batch_delay=migration_section.get("batch_delay", 1.0),

        # SMB 設定
        smb_user=source_section.get("smb_user"),
        smb_password=source_section.get("smb_password"),

        # Synology DB 設定
        synology_db_host=synology_section.get("db_host"),
        synology_db_port=synology_section.get("db_port", 5432),
        synology_db_user=synology_section.get("db_user"),
        synology_db_password=synology_section.get("db_password"),
        synology_db_name=synology_section.get("db_name", "synofoto"),
    )
```

**Step 4: テストを実行して成功を確認**

Run: `cd /home/shishi/dev/src/github.com/shishi/synology_to_immich/.worktrees/feature-migration && nix develop -c pytest tests/test_config.py -v`
Expected: PASS (5 tests)

**Step 5: コミット**

```bash
git add src/synology_to_immich/config.py tests/test_config.py
git commit -m "feat: add Config class for loading settings from TOML files"
```

---

## Phase 2: Progress Tracker（進捗管理）

### Task 3: ProgressTracker - 基本 CRUD

**Files:**
- Create: `src/synology_to_immich/progress.py`
- Create: `tests/test_progress.py`

**Step 1: ProgressTracker のテストを書く**

`tests/test_progress.py`:
```python
"""
進捗管理（ProgressTracker）のテスト

SQLite を使った移行進捗の追跡機能をテストする
"""

import pytest
from pathlib import Path
from synology_to_immich.progress import ProgressTracker, FileStatus


class TestProgressTracker:
    """ProgressTracker クラスのテスト"""

    def test_create_database(self, tmp_path: Path):
        """データベースが正しく作成されることを確認"""
        # Arrange
        db_path = tmp_path / "progress.db"

        # Act
        tracker = ProgressTracker(db_path)

        # Assert
        assert db_path.exists()
        tracker.close()

    def test_record_success(self, tmp_path: Path):
        """成功した移行を記録できることを確認"""
        # Arrange
        db_path = tmp_path / "progress.db"
        tracker = ProgressTracker(db_path)

        # Act
        tracker.record_file(
            source_path="/photos/IMG_001.jpg",
            source_hash="abc123",
            source_size=1024,
            source_mtime="2024-01-15T10:30:00",
            immich_asset_id="asset-uuid-001",
            status=FileStatus.SUCCESS,
        )

        # Assert
        result = tracker.get_file("/photos/IMG_001.jpg")
        assert result is not None
        assert result["source_hash"] == "abc123"
        assert result["status"] == "success"
        tracker.close()

    def test_is_migrated(self, tmp_path: Path):
        """ファイルが移行済みかどうかを判定できることを確認"""
        # Arrange
        db_path = tmp_path / "progress.db"
        tracker = ProgressTracker(db_path)
        tracker.record_file(
            source_path="/photos/IMG_001.jpg",
            source_hash="abc123",
            source_size=1024,
            source_mtime="2024-01-15T10:30:00",
            immich_asset_id="asset-uuid-001",
            status=FileStatus.SUCCESS,
        )

        # Act & Assert
        assert tracker.is_migrated("/photos/IMG_001.jpg") is True
        assert tracker.is_migrated("/photos/IMG_002.jpg") is False
        tracker.close()

    def test_get_pending_files(self, tmp_path: Path):
        """未移行ファイルを取得できることを確認"""
        # Arrange
        db_path = tmp_path / "progress.db"
        tracker = ProgressTracker(db_path)

        # 1つ成功、1つ失敗を記録
        tracker.record_file(
            source_path="/photos/success.jpg",
            source_hash="abc",
            source_size=100,
            source_mtime="2024-01-15",
            immich_asset_id="asset-1",
            status=FileStatus.SUCCESS,
        )
        tracker.record_file(
            source_path="/photos/failed.jpg",
            source_hash="def",
            source_size=200,
            source_mtime="2024-01-15",
            immich_asset_id=None,
            status=FileStatus.FAILED,
        )

        # Act
        failed_files = tracker.get_files_by_status(FileStatus.FAILED)

        # Assert
        assert len(failed_files) == 1
        assert failed_files[0]["source_path"] == "/photos/failed.jpg"
        tracker.close()

    def test_get_statistics(self, tmp_path: Path):
        """統計情報を取得できることを確認"""
        # Arrange
        db_path = tmp_path / "progress.db"
        tracker = ProgressTracker(db_path)

        # 3つのファイルを異なるステータスで記録
        for i, status in enumerate([FileStatus.SUCCESS, FileStatus.SUCCESS, FileStatus.FAILED]):
            tracker.record_file(
                source_path=f"/photos/IMG_{i}.jpg",
                source_hash=f"hash{i}",
                source_size=100,
                source_mtime="2024-01-15",
                immich_asset_id=f"asset-{i}" if status == FileStatus.SUCCESS else None,
                status=status,
            )

        # Act
        stats = tracker.get_statistics()

        # Assert
        assert stats["total"] == 3
        assert stats["success"] == 2
        assert stats["failed"] == 1
        assert stats["unsupported"] == 0
        tracker.close()
```

**Step 2: テストを実行して失敗を確認**

Run: `cd /home/shishi/dev/src/github.com/shishi/synology_to_immich/.worktrees/feature-migration && nix develop -c pytest tests/test_progress.py -v`
Expected: FAIL with "cannot import name 'ProgressTracker'"

**Step 3: ProgressTracker を実装**

`src/synology_to_immich/progress.py`:
```python
"""
進捗管理モジュール

SQLite データベースを使って移行の進捗を追跡する。
- 移行済みファイルの記録
- 失敗/未対応ファイルの記録
- 増分移行のための状態管理
"""

import sqlite3
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Optional


class FileStatus(Enum):
    """ファイルの移行ステータス"""
    SUCCESS = "success"          # 移行成功
    FAILED = "failed"            # 移行失敗（リトライ可能）
    UNSUPPORTED = "unsupported"  # 未対応形式（リトライ不要）


class ProgressTracker:
    """
    移行進捗を SQLite で管理するクラス

    Attributes:
        db_path: SQLite データベースファイルのパス
    """

    def __init__(self, db_path: Path):
        """
        ProgressTracker を初期化し、必要なテーブルを作成する

        Args:
            db_path: データベースファイルのパス
        """
        self.db_path = db_path
        self._conn = sqlite3.connect(str(db_path))
        self._conn.row_factory = sqlite3.Row  # 結果を辞書形式で取得
        self._create_tables()

    def _create_tables(self):
        """必要なテーブルを作成する"""
        cursor = self._conn.cursor()

        # 移行済みファイルテーブル
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS migrated_files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_path TEXT UNIQUE NOT NULL,
                source_hash TEXT,
                source_size INTEGER,
                source_mtime TEXT,
                immich_asset_id TEXT,
                migrated_at TEXT NOT NULL,
                status TEXT NOT NULL
            )
        """)

        # アルバムテーブル
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS migrated_albums (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                synology_album_id INTEGER,
                synology_album_name TEXT,
                immich_album_id TEXT,
                created_at TEXT NOT NULL
            )
        """)

        # インデックス作成
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_source_path
            ON migrated_files(source_path)
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_status
            ON migrated_files(status)
        """)

        self._conn.commit()

    def record_file(
        self,
        source_path: str,
        source_hash: Optional[str],
        source_size: int,
        source_mtime: str,
        immich_asset_id: Optional[str],
        status: FileStatus,
    ):
        """
        ファイルの移行結果を記録する

        Args:
            source_path: 元ファイルのパス
            source_hash: ファイルの SHA256 ハッシュ
            source_size: ファイルサイズ（バイト）
            source_mtime: 元ファイルの更新日時
            immich_asset_id: Immich 側のアセット ID
            status: 移行ステータス
        """
        cursor = self._conn.cursor()
        now = datetime.now().isoformat()

        # UPSERT（存在すれば更新、なければ挿入）
        cursor.execute("""
            INSERT INTO migrated_files
            (source_path, source_hash, source_size, source_mtime, immich_asset_id, migrated_at, status)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_path) DO UPDATE SET
                source_hash = excluded.source_hash,
                source_size = excluded.source_size,
                source_mtime = excluded.source_mtime,
                immich_asset_id = excluded.immich_asset_id,
                migrated_at = excluded.migrated_at,
                status = excluded.status
        """, (source_path, source_hash, source_size, source_mtime, immich_asset_id, now, status.value))

        self._conn.commit()

    def get_file(self, source_path: str) -> Optional[dict]:
        """
        指定パスのファイル情報を取得する

        Args:
            source_path: 元ファイルのパス

        Returns:
            ファイル情報の辞書、存在しない場合は None
        """
        cursor = self._conn.cursor()
        cursor.execute(
            "SELECT * FROM migrated_files WHERE source_path = ?",
            (source_path,)
        )
        row = cursor.fetchone()
        return dict(row) if row else None

    def is_migrated(self, source_path: str) -> bool:
        """
        ファイルが正常に移行済みかどうかを判定する

        Args:
            source_path: 元ファイルのパス

        Returns:
            True: 移行成功済み
            False: 未移行または失敗
        """
        file_info = self.get_file(source_path)
        if file_info is None:
            return False
        return file_info["status"] == FileStatus.SUCCESS.value

    def get_files_by_status(self, status: FileStatus) -> list[dict]:
        """
        指定ステータスのファイル一覧を取得する

        Args:
            status: フィルタするステータス

        Returns:
            ファイル情報のリスト
        """
        cursor = self._conn.cursor()
        cursor.execute(
            "SELECT * FROM migrated_files WHERE status = ?",
            (status.value,)
        )
        return [dict(row) for row in cursor.fetchall()]

    def get_statistics(self) -> dict:
        """
        移行統計を取得する

        Returns:
            統計情報の辞書
        """
        cursor = self._conn.cursor()

        # 全件数
        cursor.execute("SELECT COUNT(*) FROM migrated_files")
        total = cursor.fetchone()[0]

        # ステータス別件数
        stats = {"total": total, "success": 0, "failed": 0, "unsupported": 0}

        for status in FileStatus:
            cursor.execute(
                "SELECT COUNT(*) FROM migrated_files WHERE status = ?",
                (status.value,)
            )
            stats[status.value] = cursor.fetchone()[0]

        return stats

    def close(self):
        """データベース接続を閉じる"""
        self._conn.close()
```

**Step 4: テストを実行して成功を確認**

Run: `cd /home/shishi/dev/src/github.com/shishi/synology_to_immich/.worktrees/feature-migration && nix develop -c pytest tests/test_progress.py -v`
Expected: PASS (5 tests)

**Step 5: コミット**

```bash
git add src/synology_to_immich/progress.py tests/test_progress.py
git commit -m "feat: add ProgressTracker for SQLite-based migration progress tracking"
```

---

### Task 4: ProgressTracker - アルバム管理

**Files:**
- Modify: `src/synology_to_immich/progress.py`
- Modify: `tests/test_progress.py`

**Step 1: アルバム管理のテストを追加**

`tests/test_progress.py` に追加:
```python
class TestProgressTrackerAlbums:
    """ProgressTracker のアルバム管理テスト"""

    def test_record_album(self, tmp_path: Path):
        """アルバムを記録できることを確認"""
        # Arrange
        db_path = tmp_path / "progress.db"
        tracker = ProgressTracker(db_path)

        # Act
        tracker.record_album(
            synology_album_id=123,
            synology_album_name="Vacation 2024",
            immich_album_id="immich-album-uuid",
        )

        # Assert
        album = tracker.get_album_by_synology_id(123)
        assert album is not None
        assert album["synology_album_name"] == "Vacation 2024"
        assert album["immich_album_id"] == "immich-album-uuid"
        tracker.close()

    def test_get_all_albums(self, tmp_path: Path):
        """全アルバムを取得できることを確認"""
        # Arrange
        db_path = tmp_path / "progress.db"
        tracker = ProgressTracker(db_path)
        tracker.record_album(1, "Album A", "immich-a")
        tracker.record_album(2, "Album B", "immich-b")

        # Act
        albums = tracker.get_all_albums()

        # Assert
        assert len(albums) == 2
        tracker.close()
```

**Step 2: テストを実行して失敗を確認**

Run: `cd /home/shishi/dev/src/github.com/shishi/synology_to_immich/.worktrees/feature-migration && nix develop -c pytest tests/test_progress.py::TestProgressTrackerAlbums -v`
Expected: FAIL with "ProgressTracker' object has no attribute 'record_album'"

**Step 3: アルバム管理メソッドを実装**

`src/synology_to_immich/progress.py` の `ProgressTracker` クラスに追加:
```python
    def record_album(
        self,
        synology_album_id: int,
        synology_album_name: str,
        immich_album_id: str,
    ):
        """
        アルバムの移行結果を記録する

        Args:
            synology_album_id: Synology Photos のアルバム ID
            synology_album_name: アルバム名
            immich_album_id: Immich 側のアルバム ID
        """
        cursor = self._conn.cursor()
        now = datetime.now().isoformat()

        cursor.execute("""
            INSERT INTO migrated_albums
            (synology_album_id, synology_album_name, immich_album_id, created_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(synology_album_id) DO UPDATE SET
                synology_album_name = excluded.synology_album_name,
                immich_album_id = excluded.immich_album_id,
                created_at = excluded.created_at
        """, (synology_album_id, synology_album_name, immich_album_id, now))

        self._conn.commit()

    def get_album_by_synology_id(self, synology_album_id: int) -> Optional[dict]:
        """
        Synology アルバム ID でアルバム情報を取得する

        Args:
            synology_album_id: Synology Photos のアルバム ID

        Returns:
            アルバム情報の辞書、存在しない場合は None
        """
        cursor = self._conn.cursor()
        cursor.execute(
            "SELECT * FROM migrated_albums WHERE synology_album_id = ?",
            (synology_album_id,)
        )
        row = cursor.fetchone()
        return dict(row) if row else None

    def get_all_albums(self) -> list[dict]:
        """
        全アルバムを取得する

        Returns:
            アルバム情報のリスト
        """
        cursor = self._conn.cursor()
        cursor.execute("SELECT * FROM migrated_albums")
        return [dict(row) for row in cursor.fetchall()]
```

また、`_create_tables` メソッドの `migrated_albums` テーブルに UNIQUE 制約を追加:
```python
        # アルバムテーブル
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS migrated_albums (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                synology_album_id INTEGER UNIQUE,
                synology_album_name TEXT,
                immich_album_id TEXT,
                created_at TEXT NOT NULL
            )
        """)
```

**Step 4: テストを実行して成功を確認**

Run: `cd /home/shishi/dev/src/github.com/shishi/synology_to_immich/.worktrees/feature-migration && nix develop -c pytest tests/test_progress.py -v`
Expected: PASS (7 tests)

**Step 5: コミット**

```bash
git add src/synology_to_immich/progress.py tests/test_progress.py
git commit -m "feat: add album tracking to ProgressTracker"
```

---

## Phase 3: ファイル読み取り

### Task 5: LocalFileReader - ローカルファイルスキャン

**Files:**
- Create: `src/synology_to_immich/readers/__init__.py`
- Create: `src/synology_to_immich/readers/base.py`
- Create: `src/synology_to_immich/readers/local.py`
- Create: `tests/test_readers.py`

**Step 1: FileReader 抽象クラスとテストを作成**

`tests/test_readers.py`:
```python
"""
ファイル読み取りのテスト

ローカルファイルと SMB 経由のファイル読み取りをテストする
"""

import pytest
from pathlib import Path
from synology_to_immich.readers.local import LocalFileReader


class TestLocalFileReader:
    """LocalFileReader のテスト"""

    def test_list_files(self, tmp_path: Path):
        """ファイル一覧を取得できることを確認"""
        # Arrange: テスト用ファイルを作成
        (tmp_path / "photo1.jpg").write_bytes(b"fake jpg")
        (tmp_path / "photo2.png").write_bytes(b"fake png")
        (tmp_path / "subdir").mkdir()
        (tmp_path / "subdir" / "photo3.heic").write_bytes(b"fake heic")

        reader = LocalFileReader(str(tmp_path))

        # Act
        files = list(reader.list_files())

        # Assert
        assert len(files) == 3
        paths = [f.path for f in files]
        assert any("photo1.jpg" in p for p in paths)
        assert any("photo3.heic" in p for p in paths)

    def test_excludes_eadir(self, tmp_path: Path):
        """@eaDir が除外されることを確認"""
        # Arrange
        (tmp_path / "photo.jpg").write_bytes(b"real photo")
        (tmp_path / "@eaDir").mkdir()
        (tmp_path / "@eaDir" / "thumb.jpg").write_bytes(b"thumbnail")

        reader = LocalFileReader(str(tmp_path))

        # Act
        files = list(reader.list_files())

        # Assert
        assert len(files) == 1
        assert "@eaDir" not in files[0].path

    def test_excludes_system_files(self, tmp_path: Path):
        """.DS_Store や Thumbs.db が除外されることを確認"""
        # Arrange
        (tmp_path / "photo.jpg").write_bytes(b"real photo")
        (tmp_path / ".DS_Store").write_bytes(b"mac file")
        (tmp_path / "Thumbs.db").write_bytes(b"windows file")

        reader = LocalFileReader(str(tmp_path))

        # Act
        files = list(reader.list_files())

        # Assert
        assert len(files) == 1

    def test_read_file(self, tmp_path: Path):
        """ファイル内容を読み取れることを確認"""
        # Arrange
        content = b"file content here"
        (tmp_path / "test.jpg").write_bytes(content)
        reader = LocalFileReader(str(tmp_path))

        # Act
        data = reader.read_file(str(tmp_path / "test.jpg"))

        # Assert
        assert data == content

    def test_file_info_includes_metadata(self, tmp_path: Path):
        """ファイル情報にメタデータが含まれることを確認"""
        # Arrange
        (tmp_path / "photo.jpg").write_bytes(b"x" * 1024)
        reader = LocalFileReader(str(tmp_path))

        # Act
        files = list(reader.list_files())

        # Assert
        assert len(files) == 1
        file_info = files[0]
        assert file_info.size == 1024
        assert file_info.mtime is not None
```

**Step 2: テストを実行して失敗を確認**

Run: `cd /home/shishi/dev/src/github.com/shishi/synology_to_immich/.worktrees/feature-migration && nix develop -c pytest tests/test_readers.py -v`
Expected: FAIL with "No module named 'synology_to_immich.readers'"

**Step 3: 基底クラスと LocalFileReader を実装**

`src/synology_to_immich/readers/__init__.py`:
```python
"""
ファイル読み取りモジュール

ローカルファイルシステムと SMB からのファイル読み取りを提供する
"""

from .base import FileInfo, FileReader
from .local import LocalFileReader

__all__ = ["FileInfo", "FileReader", "LocalFileReader"]
```

`src/synology_to_immich/readers/base.py`:
```python
"""
ファイル読み取りの基底クラス

ローカルファイルと SMB で共通のインターフェースを定義する
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Iterator, Optional


@dataclass
class FileInfo:
    """
    ファイルの基本情報

    Attributes:
        path: ファイルの完全パス
        size: ファイルサイズ（バイト）
        mtime: 更新日時（ISO 8601 形式の文字列）
    """
    path: str
    size: int
    mtime: str


# 除外するパターン（ディレクトリ名またはファイル名）
EXCLUDE_PATTERNS = [
    "@eaDir",       # Synology メタデータフォルダ
    ".DS_Store",    # macOS
    "Thumbs.db",    # Windows
    ".thumbnail",   # サムネイルフォルダ
    "#recycle",     # Synology ゴミ箱
]


class FileReader(ABC):
    """
    ファイル読み取りの抽象基底クラス

    ローカルファイルと SMB で共通のインターフェースを提供する
    """

    @abstractmethod
    def list_files(self) -> Iterator[FileInfo]:
        """
        ディレクトリ内の全ファイルを再帰的に列挙する

        Yields:
            FileInfo: 各ファイルの情報
        """
        pass

    @abstractmethod
    def read_file(self, path: str) -> bytes:
        """
        ファイルの内容を読み取る

        Args:
            path: ファイルパス

        Returns:
            ファイルの内容（バイト列）
        """
        pass

    def should_exclude(self, path: str) -> bool:
        """
        パスが除外対象かどうかを判定する

        Args:
            path: チェックするパス

        Returns:
            True: 除外すべき
            False: 処理すべき
        """
        for pattern in EXCLUDE_PATTERNS:
            if pattern in path:
                return True
        return False
```

`src/synology_to_immich/readers/local.py`:
```python
"""
ローカルファイルシステムからの読み取り

ローカルまたはマウントされたディレクトリからファイルを読み取る
"""

from datetime import datetime
from pathlib import Path
from typing import Iterator

from .base import FileInfo, FileReader


class LocalFileReader(FileReader):
    """
    ローカルファイルシステムからファイルを読み取るクラス

    Attributes:
        base_path: 読み取り対象のベースディレクトリ
    """

    def __init__(self, base_path: str):
        """
        LocalFileReader を初期化する

        Args:
            base_path: ベースディレクトリのパス
        """
        self.base_path = Path(base_path)

    def list_files(self) -> Iterator[FileInfo]:
        """
        ディレクトリ内の全ファイルを再帰的に列挙する

        @eaDir や .DS_Store などのシステムファイルは除外される

        Yields:
            FileInfo: 各ファイルの情報
        """
        for path in self.base_path.rglob("*"):
            # ディレクトリはスキップ
            if path.is_dir():
                continue

            # 除外パターンに一致するものはスキップ
            if self.should_exclude(str(path)):
                continue

            # ファイル情報を取得
            stat = path.stat()
            mtime = datetime.fromtimestamp(stat.st_mtime).isoformat()

            yield FileInfo(
                path=str(path),
                size=stat.st_size,
                mtime=mtime,
            )

    def read_file(self, path: str) -> bytes:
        """
        ファイルの内容を読み取る

        Args:
            path: ファイルパス

        Returns:
            ファイルの内容（バイト列）
        """
        return Path(path).read_bytes()
```

**Step 4: テストを実行して成功を確認**

Run: `cd /home/shishi/dev/src/github.com/shishi/synology_to_immich/.worktrees/feature-migration && nix develop -c pytest tests/test_readers.py -v`
Expected: PASS (5 tests)

**Step 5: コミット**

```bash
git add src/synology_to_immich/readers/ tests/test_readers.py
git commit -m "feat: add LocalFileReader for scanning local files"
```

---

### Task 6: SmbFileReader - SMB ファイルアクセス

**Files:**
- Create: `src/synology_to_immich/readers/smb.py`
- Modify: `src/synology_to_immich/readers/__init__.py`
- Modify: `tests/test_readers.py`

**Step 1: SMB のテストを追加（モック使用）**

`tests/test_readers.py` に追加:
```python
from unittest.mock import Mock, patch, MagicMock
from synology_to_immich.readers.smb import SmbFileReader, parse_smb_url


class TestParseSmbUrl:
    """SMB URL パースのテスト"""

    def test_parse_basic_url(self):
        """基本的な SMB URL をパースできることを確認"""
        # Act
        result = parse_smb_url("smb://192.168.1.1/share/path/to/photos")

        # Assert
        assert result["host"] == "192.168.1.1"
        assert result["share"] == "share"
        assert result["path"] == "/path/to/photos"

    def test_parse_url_with_port(self):
        """ポート付き SMB URL をパースできることを確認"""
        # Act
        result = parse_smb_url("smb://192.168.1.1:445/share/photos")

        # Assert
        assert result["host"] == "192.168.1.1"
        assert result["port"] == 445
        assert result["share"] == "share"

    def test_parse_url_minimal(self):
        """最小限の SMB URL をパースできることを確認"""
        # Act
        result = parse_smb_url("smb://localhost/homes")

        # Assert
        assert result["host"] == "localhost"
        assert result["share"] == "homes"
        assert result["path"] == ""


class TestSmbFileReader:
    """SmbFileReader のテスト（モック使用）"""

    @patch("synology_to_immich.readers.smb.smbclient")
    def test_list_files_mock(self, mock_smbclient):
        """SMB ファイル一覧取得のテスト（モック）"""
        # Arrange: モックのセットアップ
        mock_entry1 = MagicMock()
        mock_entry1.name = "photo.jpg"
        mock_entry1.path = "\\\\host\\share\\photo.jpg"
        mock_entry1.is_dir.return_value = False
        mock_entry1.stat.return_value.st_size = 1024
        mock_entry1.stat.return_value.st_mtime = 1700000000.0

        mock_smbclient.scandir.return_value.__enter__ = Mock(return_value=[mock_entry1])
        mock_smbclient.scandir.return_value.__exit__ = Mock(return_value=False)

        reader = SmbFileReader(
            "smb://192.168.1.1/share",
            username="user",
            password="pass",
        )

        # scandir が再帰的に呼ばれるので、最初の呼び出しだけファイルを返す
        def scandir_side_effect(path):
            if path == "\\\\192.168.1.1\\share":
                mock_ctx = MagicMock()
                mock_ctx.__enter__ = Mock(return_value=[mock_entry1])
                mock_ctx.__exit__ = Mock(return_value=False)
                return mock_ctx
            else:
                mock_ctx = MagicMock()
                mock_ctx.__enter__ = Mock(return_value=[])
                mock_ctx.__exit__ = Mock(return_value=False)
                return mock_ctx

        mock_smbclient.scandir.side_effect = scandir_side_effect

        # Act
        files = list(reader.list_files())

        # Assert
        assert len(files) == 1
        assert "photo.jpg" in files[0].path
```

**Step 2: テストを実行して失敗を確認**

Run: `cd /home/shishi/dev/src/github.com/shishi/synology_to_immich/.worktrees/feature-migration && nix develop -c pytest tests/test_readers.py::TestParseSmbUrl -v`
Expected: FAIL with "cannot import name 'SmbFileReader'"

**Step 3: SmbFileReader を実装**

`src/synology_to_immich/readers/smb.py`:
```python
"""
SMB ファイルアクセスモジュール

smbprotocol を使用して SMB 共有からファイルを読み取る
"""

import re
from datetime import datetime
from typing import Iterator, Optional

import smbclient

from .base import FileInfo, FileReader


def parse_smb_url(url: str) -> dict:
    """
    SMB URL をパースしてコンポーネントに分解する

    Args:
        url: SMB URL (例: smb://host:port/share/path)

    Returns:
        パース結果の辞書:
        - host: ホスト名または IP
        - port: ポート番号（省略時は None）
        - share: 共有名
        - path: 共有内のパス
    """
    # smb://host:port/share/path の形式をパース
    pattern = r"^smb://([^:/]+)(?::(\d+))?/([^/]+)(.*)$"
    match = re.match(pattern, url)

    if not match:
        raise ValueError(f"無効な SMB URL: {url}")

    host = match.group(1)
    port = int(match.group(2)) if match.group(2) else None
    share = match.group(3)
    path = match.group(4) or ""

    return {
        "host": host,
        "port": port,
        "share": share,
        "path": path,
    }


class SmbFileReader(FileReader):
    """
    SMB 共有からファイルを読み取るクラス

    smbprotocol ライブラリを使用して、リモートの SMB 共有に
    アクセスする。認証情報を指定することで、保護された
    共有にもアクセスできる。

    Attributes:
        host: SMB サーバーのホスト名または IP
        share: 共有名
        base_path: 共有内のベースパス
        username: 認証ユーザー名
        password: 認証パスワード
    """

    def __init__(
        self,
        smb_url: str,
        username: Optional[str] = None,
        password: Optional[str] = None,
    ):
        """
        SmbFileReader を初期化する

        Args:
            smb_url: SMB URL (例: smb://192.168.1.1/share/path)
            username: 認証ユーザー名
            password: 認証パスワード
        """
        parsed = parse_smb_url(smb_url)
        self.host = parsed["host"]
        self.port = parsed["port"] or 445
        self.share = parsed["share"]
        self.base_path = parsed["path"]
        self.username = username
        self.password = password

        # 認証情報を登録
        if username and password:
            smbclient.register_session(
                self.host,
                username=username,
                password=password,
                port=self.port,
            )

    def _get_smb_path(self, path: str = "") -> str:
        """
        SMB UNC パスを構築する

        Args:
            path: ベースパスからの相対パス

        Returns:
            完全な UNC パス (例: \\\\host\\share\\path)
        """
        full_path = f"{self.base_path}/{path}".replace("//", "/").strip("/")
        return f"\\\\{self.host}\\{self.share}\\{full_path}".rstrip("\\")

    def list_files(self) -> Iterator[FileInfo]:
        """
        SMB 共有内の全ファイルを再帰的に列挙する

        @eaDir などの除外パターンに一致するものはスキップされる

        Yields:
            FileInfo: 各ファイルの情報
        """
        base_smb_path = self._get_smb_path()
        yield from self._scan_directory(base_smb_path)

    def _scan_directory(self, smb_path: str) -> Iterator[FileInfo]:
        """
        ディレクトリを再帰的にスキャンする

        Args:
            smb_path: スキャンする SMB パス

        Yields:
            FileInfo: 各ファイルの情報
        """
        try:
            with smbclient.scandir(smb_path) as entries:
                for entry in entries:
                    # 除外パターンのチェック
                    if self.should_exclude(entry.name):
                        continue

                    if entry.is_dir():
                        # ディレクトリは再帰的にスキャン
                        yield from self._scan_directory(entry.path)
                    else:
                        # ファイルの情報を取得
                        stat = entry.stat()
                        mtime = datetime.fromtimestamp(stat.st_mtime).isoformat()

                        yield FileInfo(
                            path=entry.path,
                            size=stat.st_size,
                            mtime=mtime,
                        )
        except Exception as e:
            # スキャンエラーはログして続行
            print(f"Warning: ディレクトリスキャンエラー {smb_path}: {e}")

    def read_file(self, path: str) -> bytes:
        """
        SMB 共有からファイルを読み取る

        Args:
            path: ファイルの SMB パス

        Returns:
            ファイルの内容（バイト列）
        """
        with smbclient.open_file(path, mode="rb") as f:
            return f.read()
```

`src/synology_to_immich/readers/__init__.py` を更新:
```python
"""
ファイル読み取りモジュール

ローカルファイルシステムと SMB からのファイル読み取りを提供する
"""

from .base import FileInfo, FileReader, EXCLUDE_PATTERNS
from .local import LocalFileReader
from .smb import SmbFileReader, parse_smb_url

__all__ = [
    "FileInfo",
    "FileReader",
    "EXCLUDE_PATTERNS",
    "LocalFileReader",
    "SmbFileReader",
    "parse_smb_url",
]
```

**Step 4: テストを実行して成功を確認**

Run: `cd /home/shishi/dev/src/github.com/shishi/synology_to_immich/.worktrees/feature-migration && nix develop -c pytest tests/test_readers.py -v`
Expected: PASS (9 tests)

**Step 5: コミット**

```bash
git add src/synology_to_immich/readers/ tests/test_readers.py
git commit -m "feat: add SmbFileReader for SMB file access"
```

---

## Phase 4: Immich クライアント

### Task 7: ImmichClient - 基本アップロード

**Files:**
- Create: `src/synology_to_immich/immich.py`
- Create: `tests/test_immich.py`

**Step 1: ImmichClient のテストを書く（モック使用）**

`tests/test_immich.py`:
```python
"""
Immich API クライアントのテスト

httpx を使用した Immich API との通信をテストする（モック使用）
"""

import pytest
from unittest.mock import Mock, patch, MagicMock
import httpx

from synology_to_immich.immich import ImmichClient, ImmichUploadResult


class TestImmichClient:
    """ImmichClient のテスト"""

    @patch("synology_to_immich.immich.httpx.Client")
    def test_upload_asset_success(self, mock_client_class):
        """アセットのアップロードが成功することを確認"""
        # Arrange
        mock_client = MagicMock()
        mock_client_class.return_value.__enter__ = Mock(return_value=mock_client)
        mock_client_class.return_value.__exit__ = Mock(return_value=False)

        mock_response = Mock()
        mock_response.status_code = 201
        mock_response.json.return_value = {
            "id": "asset-uuid-123",
            "status": "created",
        }
        mock_client.post.return_value = mock_response

        client = ImmichClient(
            base_url="http://localhost:2283",
            api_key="test-api-key",
        )

        # Act
        result = client.upload_asset(
            file_data=b"fake image data",
            filename="photo.jpg",
            created_at="2024-01-15T10:30:00",
        )

        # Assert
        assert result.success is True
        assert result.asset_id == "asset-uuid-123"

    @patch("synology_to_immich.immich.httpx.Client")
    def test_upload_asset_unsupported_format(self, mock_client_class):
        """未対応形式のエラーを正しく処理することを確認"""
        # Arrange
        mock_client = MagicMock()
        mock_client_class.return_value.__enter__ = Mock(return_value=mock_client)
        mock_client_class.return_value.__exit__ = Mock(return_value=False)

        mock_response = Mock()
        mock_response.status_code = 400
        mock_response.json.return_value = {
            "error": "Bad Request",
            "message": "Unsupported file type",
        }
        mock_client.post.return_value = mock_response

        client = ImmichClient(
            base_url="http://localhost:2283",
            api_key="test-api-key",
        )

        # Act
        result = client.upload_asset(
            file_data=b"fake data",
            filename="unknown.xyz",
            created_at="2024-01-15T10:30:00",
        )

        # Assert
        assert result.success is False
        assert result.is_unsupported is True

    @patch("synology_to_immich.immich.httpx.Client")
    def test_create_album(self, mock_client_class):
        """アルバム作成が成功することを確認"""
        # Arrange
        mock_client = MagicMock()
        mock_client_class.return_value.__enter__ = Mock(return_value=mock_client)
        mock_client_class.return_value.__exit__ = Mock(return_value=False)

        mock_response = Mock()
        mock_response.status_code = 201
        mock_response.json.return_value = {
            "id": "album-uuid-456",
            "albumName": "Vacation 2024",
        }
        mock_client.post.return_value = mock_response

        client = ImmichClient(
            base_url="http://localhost:2283",
            api_key="test-api-key",
        )

        # Act
        album_id = client.create_album("Vacation 2024")

        # Assert
        assert album_id == "album-uuid-456"

    @patch("synology_to_immich.immich.httpx.Client")
    def test_add_assets_to_album(self, mock_client_class):
        """アルバムへのアセット追加が成功することを確認"""
        # Arrange
        mock_client = MagicMock()
        mock_client_class.return_value.__enter__ = Mock(return_value=mock_client)
        mock_client_class.return_value.__exit__ = Mock(return_value=False)

        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "success": [{"id": "asset-1"}, {"id": "asset-2"}],
        }
        mock_client.put.return_value = mock_response

        client = ImmichClient(
            base_url="http://localhost:2283",
            api_key="test-api-key",
        )

        # Act
        result = client.add_assets_to_album(
            album_id="album-uuid",
            asset_ids=["asset-1", "asset-2"],
        )

        # Assert
        assert result is True
```

**Step 2: テストを実行して失敗を確認**

Run: `cd /home/shishi/dev/src/github.com/shishi/synology_to_immich/.worktrees/feature-migration && nix develop -c pytest tests/test_immich.py -v`
Expected: FAIL with "No module named 'synology_to_immich.immich'"

**Step 3: ImmichClient を実装**

`src/synology_to_immich/immich.py`:
```python
"""
Immich API クライアント

Immich サーバーとの通信を行い、アセットのアップロードと
アルバム管理を行う。
"""

import mimetypes
from dataclasses import dataclass
from typing import Optional

import httpx


@dataclass
class ImmichUploadResult:
    """
    アップロード結果を表すクラス

    Attributes:
        success: アップロードが成功したかどうか
        asset_id: 成功時の Immich アセット ID
        error_message: 失敗時のエラーメッセージ
        is_unsupported: 未対応形式エラーかどうか
    """
    success: bool
    asset_id: Optional[str] = None
    error_message: Optional[str] = None
    is_unsupported: bool = False


class ImmichClient:
    """
    Immich API と通信するクライアント

    アセットのアップロード、アルバムの作成・管理などを行う。

    Attributes:
        base_url: Immich サーバーの URL
        api_key: API キー
    """

    def __init__(self, base_url: str, api_key: str):
        """
        ImmichClient を初期化する

        Args:
            base_url: Immich サーバーの URL (例: http://localhost:2283)
            api_key: Immich API キー
        """
        # 末尾のスラッシュを削除
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key

        # 共通ヘッダー
        self._headers = {
            "x-api-key": api_key,
            "Accept": "application/json",
        }

    def upload_asset(
        self,
        file_data: bytes,
        filename: str,
        created_at: str,
        live_photo_data: Optional[bytes] = None,
    ) -> ImmichUploadResult:
        """
        アセット（写真または動画）をアップロードする

        Args:
            file_data: ファイルの内容（バイト列）
            filename: ファイル名
            created_at: 撮影日時（ISO 8601 形式）
            live_photo_data: Live Photo の動画部分（オプション）

        Returns:
            ImmichUploadResult: アップロード結果
        """
        # MIME タイプを推測
        mime_type, _ = mimetypes.guess_type(filename)
        if mime_type is None:
            mime_type = "application/octet-stream"

        # multipart/form-data の構築
        files = {
            "assetData": (filename, file_data, mime_type),
        }

        # Live Photo の場合は動画も添付
        if live_photo_data:
            # 動画のファイル名を推測（.mov を追加）
            video_filename = filename.rsplit(".", 1)[0] + ".mov"
            files["livePhotoData"] = (video_filename, live_photo_data, "video/quicktime")

        # フォームデータ
        data = {
            "deviceAssetId": filename,  # ユニーク ID として使用
            "deviceId": "synology-to-immich",
            "fileCreatedAt": created_at,
            "fileModifiedAt": created_at,
        }

        try:
            with httpx.Client(timeout=60.0) as client:
                response = client.post(
                    f"{self.base_url}/api/assets",
                    headers=self._headers,
                    files=files,
                    data=data,
                )

                if response.status_code == 201:
                    # 成功
                    result = response.json()
                    return ImmichUploadResult(
                        success=True,
                        asset_id=result.get("id"),
                    )
                elif response.status_code == 400:
                    # クライアントエラー（未対応形式など）
                    error_data = response.json()
                    error_msg = error_data.get("message", "Unknown error")
                    is_unsupported = "unsupported" in error_msg.lower()
                    return ImmichUploadResult(
                        success=False,
                        error_message=error_msg,
                        is_unsupported=is_unsupported,
                    )
                else:
                    # その他のエラー
                    return ImmichUploadResult(
                        success=False,
                        error_message=f"HTTP {response.status_code}: {response.text}",
                    )

        except httpx.HTTPError as e:
            return ImmichUploadResult(
                success=False,
                error_message=f"Network error: {str(e)}",
            )

    def create_album(self, album_name: str) -> Optional[str]:
        """
        アルバムを作成する

        Args:
            album_name: アルバム名

        Returns:
            作成されたアルバムの ID、失敗時は None
        """
        try:
            with httpx.Client(timeout=30.0) as client:
                response = client.post(
                    f"{self.base_url}/api/albums",
                    headers={**self._headers, "Content-Type": "application/json"},
                    json={"albumName": album_name},
                )

                if response.status_code == 201:
                    return response.json().get("id")
                return None

        except httpx.HTTPError:
            return None

    def add_assets_to_album(self, album_id: str, asset_ids: list[str]) -> bool:
        """
        アセットをアルバムに追加する

        Args:
            album_id: アルバム ID
            asset_ids: 追加するアセット ID のリスト

        Returns:
            成功した場合は True
        """
        try:
            with httpx.Client(timeout=30.0) as client:
                response = client.put(
                    f"{self.base_url}/api/albums/{album_id}/assets",
                    headers={**self._headers, "Content-Type": "application/json"},
                    json={"ids": asset_ids},
                )

                return response.status_code == 200

        except httpx.HTTPError:
            return False

    def get_all_assets(self) -> list[dict]:
        """
        全アセットを取得する（verify コマンド用）

        Returns:
            アセット情報のリスト
        """
        assets = []
        page = 1

        try:
            with httpx.Client(timeout=60.0) as client:
                while True:
                    response = client.get(
                        f"{self.base_url}/api/assets",
                        headers=self._headers,
                        params={"page": page, "size": 1000},
                    )

                    if response.status_code != 200:
                        break

                    data = response.json()
                    if not data:
                        break

                    assets.extend(data)
                    page += 1

                    # 最後のページ
                    if len(data) < 1000:
                        break

        except httpx.HTTPError:
            pass

        return assets
```

**Step 4: テストを実行して成功を確認**

Run: `cd /home/shishi/dev/src/github.com/shishi/synology_to_immich/.worktrees/feature-migration && nix develop -c pytest tests/test_immich.py -v`
Expected: PASS (4 tests)

**Step 5: コミット**

```bash
git add src/synology_to_immich/immich.py tests/test_immich.py
git commit -m "feat: add ImmichClient for API communication"
```

---

## Phase 5: ロギング

### Task 8: ログシステムの実装

**Files:**
- Create: `src/synology_to_immich/logging.py`
- Create: `tests/test_logging.py`

**Step 1: ロギングのテストを書く**

`tests/test_logging.py`:
```python
"""
ロギングシステムのテスト

複数のログファイルへの出力と、未対応形式の特別なログ出力をテストする
"""

import pytest
from pathlib import Path
from synology_to_immich.logging import MigrationLogger


class TestMigrationLogger:
    """MigrationLogger のテスト"""

    def test_creates_log_files(self, tmp_path: Path):
        """ログファイルが作成されることを確認"""
        # Arrange & Act
        logger = MigrationLogger(tmp_path)
        logger.info("test message")
        logger.close()

        # Assert
        log_files = list(tmp_path.glob("migration_*.log"))
        assert len(log_files) == 1

    def test_logs_unsupported_format(self, tmp_path: Path):
        """未対応形式の専用ログが出力されることを確認"""
        # Arrange
        logger = MigrationLogger(tmp_path)

        # Act
        logger.log_unsupported(
            file_path="/photos/test.xyz",
            file_size=1024,
            mime_type="application/octet-stream",
            error_message="Unsupported file type",
        )
        logger.close()

        # Assert
        unsupported_logs = list(tmp_path.glob("unsupported_*.log"))
        assert len(unsupported_logs) == 1

        content = unsupported_logs[0].read_text()
        assert "/photos/test.xyz" in content
        assert "1024" in content or "1 KB" in content

    def test_logs_error(self, tmp_path: Path):
        """エラーログが出力されることを確認"""
        # Arrange
        logger = MigrationLogger(tmp_path)

        # Act
        logger.error("Something went wrong", file_path="/photos/fail.jpg")
        logger.close()

        # Assert
        error_logs = list(tmp_path.glob("errors_*.log"))
        assert len(error_logs) == 1

        content = error_logs[0].read_text()
        assert "Something went wrong" in content
        assert "/photos/fail.jpg" in content
```

**Step 2: テストを実行して失敗を確認**

Run: `cd /home/shishi/dev/src/github.com/shishi/synology_to_immich/.worktrees/feature-migration && nix develop -c pytest tests/test_logging.py -v`
Expected: FAIL with "No module named 'synology_to_immich.logging'"

**Step 3: MigrationLogger を実装**

`src/synology_to_immich/logging.py`:
```python
"""
ロギングモジュール

移行処理のログを複数のファイルに出力する:
- migration_*.log: 全ログ
- errors_*.log: エラーのみ
- unsupported_*.log: 未対応形式専用（詳細フォーマット）
"""

import logging
from datetime import datetime
from pathlib import Path
from typing import Optional


class MigrationLogger:
    """
    移行処理用のロガー

    複数のログファイルに異なる詳細度でログを出力する。
    特に未対応形式のエラーは専用の詳細フォーマットで出力する。

    Attributes:
        log_dir: ログファイルの出力先ディレクトリ
    """

    def __init__(self, log_dir: Path):
        """
        MigrationLogger を初期化し、ログファイルを作成する

        Args:
            log_dir: ログファイルの出力先ディレクトリ
        """
        self.log_dir = Path(log_dir)
        self.log_dir.mkdir(parents=True, exist_ok=True)

        # タイムスタンプ（ファイル名用）
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

        # メインログ（全ログ）
        self._main_log_path = self.log_dir / f"migration_{timestamp}.log"
        self._main_logger = self._create_logger(
            "migration",
            self._main_log_path,
            logging.DEBUG,
        )

        # エラーログ
        self._error_log_path = self.log_dir / f"errors_{timestamp}.log"
        self._error_logger = self._create_logger(
            "migration_errors",
            self._error_log_path,
            logging.ERROR,
        )

        # 未対応形式専用ログ
        self._unsupported_log_path = self.log_dir / f"unsupported_{timestamp}.log"
        self._unsupported_file = open(self._unsupported_log_path, "w", encoding="utf-8")

    def _create_logger(
        self,
        name: str,
        log_path: Path,
        level: int,
    ) -> logging.Logger:
        """
        ロガーを作成する

        Args:
            name: ロガー名
            log_path: ログファイルのパス
            level: ログレベル

        Returns:
            設定済みの Logger
        """
        logger = logging.getLogger(name)
        logger.setLevel(level)

        # ファイルハンドラー
        handler = logging.FileHandler(log_path, encoding="utf-8")
        handler.setLevel(level)

        # フォーマット
        formatter = logging.Formatter(
            "%(asctime)s [%(levelname)s] %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )
        handler.setFormatter(formatter)

        logger.addHandler(handler)
        return logger

    def debug(self, message: str, **kwargs):
        """デバッグメッセージをログに出力"""
        self._main_logger.debug(self._format_message(message, kwargs))

    def info(self, message: str, **kwargs):
        """情報メッセージをログに出力"""
        self._main_logger.info(self._format_message(message, kwargs))

    def warning(self, message: str, **kwargs):
        """警告メッセージをログに出力"""
        self._main_logger.warning(self._format_message(message, kwargs))

    def error(self, message: str, **kwargs):
        """エラーメッセージをログに出力（エラーログにも）"""
        formatted = self._format_message(message, kwargs)
        self._main_logger.error(formatted)
        self._error_logger.error(formatted)

    def log_unsupported(
        self,
        file_path: str,
        file_size: int,
        mime_type: str,
        error_message: str,
    ):
        """
        未対応形式のエラーを専用フォーマットで出力

        Args:
            file_path: ファイルパス
            file_size: ファイルサイズ（バイト）
            mime_type: 検出された MIME タイプ
            error_message: Immich からのエラーメッセージ
        """
        # 通常のエラーログにも記録
        self.error(f"Unsupported format: {file_path}")

        # 専用ログに詳細フォーマットで出力
        size_str = self._format_size(file_size)
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        self._unsupported_file.write(f"""
============================================================
⚠️  UNSUPPORTED FORMAT DETECTED
============================================================
File: {file_path}
Size: {size_str}
Attempted MIME: {mime_type}
Immich Response: "{error_message}"
Timestamp: {timestamp}
============================================================
""")
        self._unsupported_file.flush()

    def _format_message(self, message: str, kwargs: dict) -> str:
        """メッセージと追加情報をフォーマットする"""
        if not kwargs:
            return message

        extras = " | ".join(f"{k}={v}" for k, v in kwargs.items())
        return f"{message} | {extras}"

    def _format_size(self, size_bytes: int) -> str:
        """バイト数を人間が読みやすい形式に変換"""
        for unit in ["B", "KB", "MB", "GB"]:
            if size_bytes < 1024:
                return f"{size_bytes:.1f} {unit}"
            size_bytes /= 1024
        return f"{size_bytes:.1f} TB"

    def close(self):
        """ログファイルを閉じる"""
        self._unsupported_file.close()

        # ロガーのハンドラーを閉じる
        for handler in self._main_logger.handlers[:]:
            handler.close()
            self._main_logger.removeHandler(handler)

        for handler in self._error_logger.handlers[:]:
            handler.close()
            self._error_logger.removeHandler(handler)
```

**Step 4: テストを実行して成功を確認**

Run: `cd /home/shishi/dev/src/github.com/shishi/synology_to_immich/.worktrees/feature-migration && nix develop -c pytest tests/test_logging.py -v`
Expected: PASS (3 tests)

**Step 5: コミット**

```bash
git add src/synology_to_immich/logging.py tests/test_logging.py
git commit -m "feat: add MigrationLogger for multi-file logging with unsupported format tracking"
```

---

## Phase 6: メイン移行ロジック（後続タスクで追加予定）

### Task 9-15: 残りの実装タスク（概要）

以下のタスクは Phase 1-5 完了後に詳細化:

- **Task 9**: Live Photos ペアリングロジック
- **Task 10**: Synology PostgreSQL からのアルバム取得
- **Task 11**: Migrator クラス（メインオーケストレーション）
- **Task 12**: CLI コマンド（migrate）
- **Task 13**: CLI コマンド（verify）
- **Task 14**: CLI コマンド（status, retry）
- **Task 15**: 最終レポート出力

---

## テスト実行コマンド

```bash
# 全テスト実行
nix develop -c pytest -v

# カバレッジ付き
nix develop -c pytest --cov=synology_to_immich --cov-report=html

# 特定のテストファイル
nix develop -c pytest tests/test_config.py -v

# 特定のテストクラス
nix develop -c pytest tests/test_progress.py::TestProgressTracker -v
```

## 開発環境コマンド

```bash
# 開発環境に入る
cd /home/shishi/dev/src/github.com/shishi/synology_to_immich/.worktrees/feature-migration
nix develop

# コードフォーマット
black .

# リント
ruff check .

# 型チェック
mypy src/
```
