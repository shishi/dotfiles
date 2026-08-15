from pathlib import Path
from contextlib import redirect_stderr
import io
import json
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


CODEX_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CODEX_DIR))

import install_plugins


class RecordingRunner:
    def __init__(self, responses: dict[tuple[str, ...], subprocess.CompletedProcess] | None = None) -> None:
        self.calls: list[list[str]] = []
        self.responses = responses or {}

    def run(self, args: list[str]):
        self.calls.append(args)
        key = tuple(args)
        if key not in self.responses:
            raise AssertionError(f"unexpected command: {args}")
        return self.responses[key]


class MutatingRunner(RecordingRunner):
    def __init__(
        self,
        config_path: Path,
        responses: dict[tuple[str, ...], subprocess.CompletedProcess],
    ) -> None:
        super().__init__(responses)
        self.config_path = config_path

    def run(self, args: list[str]):
        if args[1:3] == ["plugin", "remove"]:
            self.config_path.write_bytes(b"cli-mutated-config\n")
        return super().run(args)


class AlwaysMutatingRunner(MutatingRunner):
    def run(self, args: list[str]):
        self.config_path.write_bytes(b"cli-mutated-config\n")
        return RecordingRunner.run(self, args)


def completed(args: list[str], payload: dict) -> subprocess.CompletedProcess:
    return subprocess.CompletedProcess(args, 0, json.dumps(payload), "")


def succeeded(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.CompletedProcess(args, 0, "", "")


class InstallPluginsTest(unittest.TestCase):
    def test_missing_codex_cli_is_a_successful_noop(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.toml"
            config_path.write_text("", encoding="utf-8")
            runner = RecordingRunner()

            status = install_plugins.reconcile(
                config_path=config_path,
                runner=runner,
                codex_path=None,
            )

        self.assertEqual(0, status)
        self.assertEqual([], runner.calls)

    def test_scalar_marketplace_config_is_rejected_without_running_cli(self) -> None:
        runner = RecordingRunner()
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.toml"
            config_path.write_text(
                "[marketplaces]\nexample = 7\n",
                encoding="utf-8",
            )

            try:
                status = install_plugins.reconcile(
                    config_path=config_path,
                    runner=runner,
                    codex_path="codex",
                )
            except Exception as error:
                self.fail(f"reconcile raised {error!r}")

        self.assertEqual(1, status)
        self.assertEqual([], runner.calls)

    def test_scalar_plugin_config_is_rejected_without_running_cli(self) -> None:
        runner = RecordingRunner()
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.toml"
            config_path.write_text(
                '[plugins]\n"tool@example" = 7\n',
                encoding="utf-8",
            )

            try:
                status = install_plugins.reconcile(
                    config_path=config_path,
                    runner=runner,
                    codex_path="codex",
                )
            except Exception as error:
                self.fail(f"reconcile raised {error!r}")

        self.assertEqual(1, status)
        self.assertEqual([], runner.calls)

    def test_local_non_app_marketplace_is_rejected_without_running_cli(self) -> None:
        runner = RecordingRunner()
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.toml"
            config_path.write_text(
                '[marketplaces.example]\nsource_type = "local"\n'
                'source = "C:/plugins/example"\n',
                encoding="utf-8",
            )

            status = install_plugins.reconcile(
                config_path=config_path,
                runner=runner,
                codex_path="codex",
            )

        self.assertEqual(1, status)
        self.assertEqual([], runner.calls)

    def test_git_marketplace_runtime_metadata_is_ignored(self) -> None:
        codex = "codex"
        marketplace_command = [codex, "plugin", "marketplace", "list", "--json"]
        plugin_command = [codex, "plugin", "list", "--json"]
        runner = RecordingRunner(
            {
                tuple(marketplace_command): completed(
                    marketplace_command,
                    {
                        "marketplaces": [
                            {
                                "name": "example",
                                "marketplaceSource": {
                                    "sourceType": "git",
                                    "source": "https://example.invalid/plugins.git",
                                },
                            }
                        ]
                    },
                ),
                tuple(plugin_command): completed(plugin_command, {"installed": []}),
            }
        )
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.toml"
            config_path.write_text(
                '[marketplaces.example]\nsource_type = "git"\n'
                'source = "https://example.invalid/plugins.git"\n'
                'last_updated = "2026-08-16T00:00:00Z"\n'
                'last_revision = "0123456789abcdef"\n',
                encoding="utf-8",
            )

            status = install_plugins.reconcile(
                config_path=config_path,
                runner=runner,
                codex_path=codex,
            )

        self.assertEqual(0, status)
        self.assertEqual([marketplace_command, plugin_command], runner.calls)

    def test_unknown_marketplace_metadata_is_rejected_without_running_cli(self) -> None:
        runner = RecordingRunner()
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.toml"
            config_path.write_text(
                '[marketplaces.example]\nsource_type = "git"\n'
                'source = "https://example.invalid/plugins.git"\n'
                'unknown_metadata = "value"\n',
                encoding="utf-8",
            )

            status = install_plugins.reconcile(
                config_path=config_path,
                runner=runner,
                codex_path="codex",
            )

        self.assertEqual(1, status)
        self.assertEqual([], runner.calls)

    def test_git_marketplace_missing_or_invalid_required_fields_are_rejected(self) -> None:
        configs = {
            "missing-source-type": (
                '[marketplaces.example]\nsource = "https://example.invalid/plugins.git"\n'
            ),
            "missing-source": '[marketplaces.example]\nsource_type = "git"\n',
            "invalid-source-type": (
                '[marketplaces.example]\nsource_type = 7\n'
                'source = "https://example.invalid/plugins.git"\n'
            ),
            "invalid-source": '[marketplaces.example]\nsource_type = "git"\nsource = 7\n',
        }

        for name, config_text in configs.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                config_path = Path(directory) / "config.toml"
                config_path.write_text(config_text, encoding="utf-8")
                runner = RecordingRunner()

                status = install_plugins.reconcile(
                    config_path=config_path,
                    runner=runner,
                    codex_path="codex",
                )

                self.assertEqual(1, status)
                self.assertEqual([], runner.calls)

    def test_converged_external_plugin_only_lists_state(self) -> None:
        codex = "codex"
        marketplace_command = [codex, "plugin", "marketplace", "list", "--json"]
        plugin_command = [codex, "plugin", "list", "--json"]
        runner = RecordingRunner(
            {
                tuple(marketplace_command): completed(
                    marketplace_command,
                    {
                        "marketplaces": [
                            {
                                "name": "example",
                                "marketplaceSource": {
                                    "sourceType": "git",
                                    "source": "https://example.invalid/plugins.git",
                                },
                            }
                        ]
                    },
                ),
                tuple(plugin_command): completed(
                    plugin_command,
                    {"installed": [{"pluginId": "tool@example"}]},
                ),
            }
        )
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.toml"
            config_path.write_text(
                '[marketplaces.example]\nsource_type = "git"\n'
                'source = "https://example.invalid/plugins.git"\n\n'
                '[plugins."tool@example"]\nenabled = true\n',
                encoding="utf-8",
            )

            status = install_plugins.reconcile(
                config_path=config_path,
                runner=runner,
                codex_path=codex,
            )

        self.assertEqual(0, status)
        self.assertEqual([marketplace_command, plugin_command], runner.calls)

    def test_runtime_app_marketplace_with_local_source_is_reconciled(self) -> None:
        codex = "codex"
        marketplace_command = [codex, "plugin", "marketplace", "list", "--json"]
        plugin_command = [codex, "plugin", "list", "--json"]
        source = "C:/Codex/plugins/openai-bundled"
        runner = RecordingRunner(
            {
                tuple(marketplace_command): completed(
                    marketplace_command,
                    {
                        "marketplaces": [
                            {
                                "name": "openai-bundled",
                                "marketplaceSource": {
                                    "sourceType": "local",
                                    "source": source,
                                },
                            }
                        ]
                    },
                ),
                tuple(plugin_command): completed(plugin_command, {"installed": []}),
            }
        )
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.toml"
            config_path.write_text(
                '[marketplaces.openai-bundled]\nsource_type = "local"\n'
                f'source = "{source}"\n',
                encoding="utf-8",
            )

            status = install_plugins.reconcile(
                config_path=config_path,
                runner=runner,
                codex_path=codex,
            )

        self.assertEqual(0, status)
        self.assertEqual([marketplace_command, plugin_command], runner.calls)

    def test_runtime_marketplace_metadata_is_not_reconciled_as_desired_state(self) -> None:
        codex = "codex"
        marketplace_command = [codex, "plugin", "marketplace", "list", "--json"]
        plugin_command = [codex, "plugin", "list", "--json"]
        runner = RecordingRunner(
            {
                tuple(marketplace_command): completed(
                    marketplace_command,
                    {
                        "marketplaces": [
                            {"name": "openai-bundled", "marketplaceSource": {}},
                            {
                                "name": "example",
                                "marketplaceSource": {
                                    "sourceType": "git",
                                    "source": "https://example.invalid/plugins.git",
                                },
                            },
                        ]
                    },
                ),
                tuple(plugin_command): completed(
                    plugin_command,
                    {"installed": [{"pluginId": "tool@example"}]},
                ),
            }
        )
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.toml"
            config_path.write_text(
                '[marketplaces.openai-bundled]\nsource_type = "local"\n'
                'source = "C:/Codex/plugins/openai-bundled"\n'
                'last_updated = "2026-08-16T00:00:00Z"\n'
                'last_revision = "runtime"\n\n'
                '[marketplaces.example]\nsource_type = "git"\n'
                'source = "https://example.invalid/plugins.git"\n\n'
                '[plugins."browser@openai-bundled"]\nenabled = true\n\n'
                '[plugins."tool@example"]\nenabled = true\n',
                encoding="utf-8",
            )
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                status = install_plugins.reconcile(
                    config_path=config_path,
                    runner=runner,
                    codex_path=codex,
                )

        self.assertEqual(0, status)
        self.assertEqual([marketplace_command, plugin_command], runner.calls)
        self.assertIn("browser@openai-bundled", stderr.getvalue())

    def test_missing_marketplace_is_added_before_enabled_plugin(self) -> None:
        codex = "codex"
        marketplace_list = [codex, "plugin", "marketplace", "list", "--json"]
        plugin_list = [codex, "plugin", "list", "--json"]
        marketplace_add = [
            codex,
            "plugin",
            "marketplace",
            "add",
            "https://example.invalid/plugins.git",
        ]
        plugin_add = [codex, "plugin", "add", "tool@example"]
        runner = RecordingRunner(
            {
                tuple(marketplace_list): completed(
                    marketplace_list, {"marketplaces": []}
                ),
                tuple(plugin_list): completed(plugin_list, {"installed": []}),
                tuple(marketplace_add): succeeded(marketplace_add),
                tuple(plugin_add): succeeded(plugin_add),
            }
        )
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.toml"
            config_path.write_text(
                '[marketplaces.example]\nsource_type = "git"\n'
                'source = "https://example.invalid/plugins.git"\n\n'
                '[plugins."tool@example"]\nenabled = true\n',
                encoding="utf-8",
            )

            status = install_plugins.reconcile(
                config_path=config_path,
                runner=runner,
                codex_path=codex,
            )

        self.assertEqual(0, status)
        self.assertEqual(
            [marketplace_list, marketplace_add, plugin_list, plugin_add],
            runner.calls,
        )

    def test_disabled_plugin_is_removed_without_adding_missing_marketplace(self) -> None:
        codex = "codex"
        marketplace_list = [codex, "plugin", "marketplace", "list", "--json"]
        plugin_list = [codex, "plugin", "list", "--json"]
        plugin_remove = [codex, "plugin", "remove", "tool@example"]
        runner = RecordingRunner(
            {
                tuple(marketplace_list): completed(
                    marketplace_list, {"marketplaces": []}
                ),
                tuple(plugin_list): completed(
                    plugin_list, {"installed": [{"pluginId": "tool@example"}]}
                ),
                tuple(plugin_remove): succeeded(plugin_remove),
            }
        )
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.toml"
            config_path.write_text(
                '[marketplaces.example]\nsource_type = "git"\n'
                'source = "https://example.invalid/plugins.git"\n\n'
                '[plugins."tool@example"]\nenabled = false\n',
                encoding="utf-8",
            )

            status = install_plugins.reconcile(
                config_path=config_path,
                runner=runner,
                codex_path=codex,
            )

        self.assertEqual(0, status)
        self.assertEqual([marketplace_list, plugin_list, plugin_remove], runner.calls)

    def test_app_supplied_plugins_are_not_managed(self) -> None:
        codex = "codex"
        marketplace_list = [codex, "plugin", "marketplace", "list", "--json"]
        plugin_list = [codex, "plugin", "list", "--json"]
        runner = RecordingRunner(
            {
                tuple(marketplace_list): completed(
                    marketplace_list, {"marketplaces": []}
                ),
                tuple(plugin_list): completed(
                    plugin_list,
                    {
                        "installed": [
                            {"pluginId": "superpowers@openai-api-curated"},
                        ]
                    },
                ),
            }
        )
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.toml"
            config_path.write_text(
                '[plugins."documents@openai-primary-runtime"]\nenabled = true\n\n'
                '[plugins."browser@openai-bundled"]\nenabled = true\n\n'
                '[plugins."codex-security@openai-api-curated"]\nenabled = true\n\n'
                '[plugins."superpowers@openai-api-curated"]\nenabled = false\n',
                encoding="utf-8",
            )

            stderr = io.StringIO()
            with redirect_stderr(stderr):
                status = install_plugins.reconcile(
                    config_path=config_path,
                    runner=runner,
                    codex_path=codex,
                )

        self.assertEqual(0, status)
        self.assertEqual([marketplace_list, plugin_list], runner.calls)
        self.assertIn("documents@openai-primary-runtime", stderr.getvalue())
        self.assertIn("browser@openai-bundled", stderr.getvalue())
        self.assertIn("codex-security@openai-api-curated", stderr.getvalue())

    def test_marketplace_list_failure_is_nonzero_and_stops(self) -> None:
        codex = "codex"
        marketplace_list = [codex, "plugin", "marketplace", "list", "--json"]
        runner = RecordingRunner(
            {
                tuple(marketplace_list): subprocess.CompletedProcess(
                    marketplace_list, 7, "", "list failed"
                )
            }
        )
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.toml"
            config_path.write_text("", encoding="utf-8")

            status = install_plugins.reconcile(
                config_path=config_path,
                runner=runner,
                codex_path=codex,
            )

        self.assertEqual(1, status)
        self.assertEqual([marketplace_list], runner.calls)

    def test_all_mutating_command_failures_are_nonzero(self) -> None:
        codex = "codex"
        marketplace_list = [codex, "plugin", "marketplace", "list", "--json"]
        plugin_list = [codex, "plugin", "list", "--json"]
        marketplace_add = [
            codex,
            "plugin",
            "marketplace",
            "add",
            "https://example.invalid/plugins.git",
        ]
        plugin_add = [codex, "plugin", "add", "tool@example"]
        plugin_remove = [codex, "plugin", "remove", "tool@example"]
        external_config = (
            '[marketplaces.example]\nsource_type = "git"\n'
            'source = "https://example.invalid/plugins.git"\n\n'
            '[plugins."tool@example"]\nenabled = true\n'
        )
        scenarios = {
            "plugin-list": (
                external_config,
                {
                    tuple(marketplace_list): completed(
                        marketplace_list, {"marketplaces": []}
                    ),
                    tuple(marketplace_add): succeeded(marketplace_add),
                    tuple(plugin_list): subprocess.CompletedProcess(
                        plugin_list, 2, "", "failed"
                    ),
                },
            ),
            "marketplace-add": (
                external_config,
                {
                    tuple(marketplace_list): completed(
                        marketplace_list, {"marketplaces": []}
                    ),
                    tuple(plugin_list): completed(plugin_list, {"installed": []}),
                    tuple(marketplace_add): subprocess.CompletedProcess(
                        marketplace_add, 3, "", "failed"
                    ),
                },
            ),
            "plugin-add": (
                external_config,
                {
                    tuple(marketplace_list): completed(
                        marketplace_list,
                        {
                            "marketplaces": [
                                {
                                    "name": "example",
                                    "marketplaceSource": {
                                        "sourceType": "git",
                                        "source": "https://example.invalid/plugins.git",
                                    },
                                }
                            ]
                        },
                    ),
                    tuple(plugin_list): completed(plugin_list, {"installed": []}),
                    tuple(plugin_add): subprocess.CompletedProcess(
                        plugin_add, 4, "", "failed"
                    ),
                },
            ),
            "plugin-remove": (
                '[marketplaces.example]\nsource_type = "git"\n'
                'source = "https://example.invalid/plugins.git"\n\n'
                '[plugins."tool@example"]\nenabled = false\n',
                {
                    tuple(marketplace_list): completed(
                        marketplace_list, {"marketplaces": []}
                    ),
                    tuple(plugin_list): completed(
                        plugin_list,
                        {"installed": [{"pluginId": "tool@example"}]},
                    ),
                    tuple(plugin_remove): subprocess.CompletedProcess(
                        plugin_remove, 5, "", "failed"
                    ),
                },
            ),
        }

        for name, (config_text, responses) in scenarios.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                config_path = Path(directory) / "config.toml"
                config_path.write_text(config_text, encoding="utf-8")
                status = install_plugins.reconcile(
                    config_path=config_path,
                    runner=RecordingRunner(responses),
                    codex_path=codex,
                )
                self.assertEqual(1, status)

    def test_invalid_config_and_source_mismatch_are_nonzero(self) -> None:
        codex = "codex"
        marketplace_list = [codex, "plugin", "marketplace", "list", "--json"]
        plugin_list = [codex, "plugin", "list", "--json"]
        source_mismatch_runner = RecordingRunner(
            {
                tuple(marketplace_list): completed(
                    marketplace_list,
                    {
                        "marketplaces": [
                            {
                                "name": "example",
                                "marketplaceSource": {
                                    "sourceType": "git",
                                    "source": "https://wrong.invalid/plugins.git",
                                },
                            }
                        ]
                    },
                ),
                tuple(plugin_list): completed(plugin_list, {"installed": []}),
            }
        )
        scenarios = {
            "malformed-toml": ("[plugins", RecordingRunner()),
            "enabled-external-without-source": (
                '[plugins."tool@example"]\nenabled = true\n',
                RecordingRunner(),
            ),
            "source-mismatch": (
                '[marketplaces.example]\nsource_type = "git"\n'
                'source = "https://example.invalid/plugins.git"\n',
                source_mismatch_runner,
            ),
        }

        for name, (config_text, runner) in scenarios.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                config_path = Path(directory) / "config.toml"
                config_path.write_text(config_text, encoding="utf-8")
                status = install_plugins.reconcile(
                    config_path=config_path,
                    runner=runner,
                    codex_path=codex,
                )
                self.assertEqual(1, status)

    def test_source_type_mismatch_is_nonzero_and_stops(self) -> None:
        codex = "codex"
        marketplace_list = [codex, "plugin", "marketplace", "list", "--json"]
        runner = RecordingRunner(
            {
                tuple(marketplace_list): completed(
                    marketplace_list,
                    {
                        "marketplaces": [
                            {
                                "name": "example",
                                "marketplaceSource": {
                                    "sourceType": "directory",
                                    "source": "https://example.invalid/plugins.git",
                                },
                            }
                        ]
                    },
                )
            }
        )
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.toml"
            config_path.write_text(
                '[marketplaces.example]\nsource_type = "git"\n'
                'source = "https://example.invalid/plugins.git"\n',
                encoding="utf-8",
            )

            status = install_plugins.reconcile(
                config_path=config_path,
                runner=runner,
                codex_path=codex,
            )

        self.assertEqual(1, status)
        self.assertEqual([marketplace_list], runner.calls)

    def test_config_bytes_are_restored_after_success_and_failure(self) -> None:
        codex = "codex"
        marketplace_list = [codex, "plugin", "marketplace", "list", "--json"]
        plugin_list = [codex, "plugin", "list", "--json"]
        plugin_remove = [codex, "plugin", "remove", "tool@example"]
        original = (
            b'[marketplaces.example]\r\nsource_type = "git"\r\n'
            b'source = "https://example.invalid/plugins.git"\r\n\r\n'
            b'[plugins."tool@example"]\r\nenabled = false\r\n'
        )

        for returncode in (0, 9):
            with self.subTest(returncode=returncode), tempfile.TemporaryDirectory() as directory:
                config_path = Path(directory) / "config.toml"
                config_path.write_bytes(original)
                runner = MutatingRunner(
                    config_path,
                    {
                        tuple(marketplace_list): completed(
                            marketplace_list, {"marketplaces": []}
                        ),
                        tuple(plugin_list): completed(
                            plugin_list,
                            {"installed": [{"pluginId": "tool@example"}]},
                        ),
                        tuple(plugin_remove): subprocess.CompletedProcess(
                            plugin_remove, returncode, "", "failed" if returncode else ""
                        ),
                    },
                )

                status = install_plugins.reconcile(
                    config_path=config_path,
                    runner=runner,
                    codex_path=codex,
                )

                self.assertEqual(0 if returncode == 0 else 1, status)
                self.assertEqual(original, config_path.read_bytes())

    def test_restore_failure_keeps_backup_and_prints_recovery_command(self) -> None:
        codex = "codex"
        marketplace_list = [codex, "plugin", "marketplace", "list", "--json"]
        plugin_list = [codex, "plugin", "list", "--json"]
        runner = RecordingRunner(
            {
                tuple(marketplace_list): completed(
                    marketplace_list, {"marketplaces": []}
                ),
                tuple(plugin_list): completed(plugin_list, {"installed": []}),
            }
        )
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.toml"
            config_path.write_text("", encoding="utf-8")
            stderr = io.StringIO()

            with patch.object(
                install_plugins.os, "replace", side_effect=OSError("restore failed")
            ), redirect_stderr(stderr):
                status = install_plugins.reconcile(
                    config_path=config_path,
                    runner=runner,
                    codex_path=codex,
                )

            backups = list(Path(directory).glob(".config.toml.restore-*"))

        self.assertEqual(1, status)
        self.assertEqual(1, len(backups))
        self.assertIn(str(backups[0].resolve()), stderr.getvalue())
        self.assertIn("--restore", stderr.getvalue())

    def test_restore_command_atomically_replaces_config(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            backup_path = Path(directory) / "config.backup"
            config_path = Path(directory) / "config.toml"
            backup_path.write_bytes(b"original\r\n")
            config_path.write_bytes(b"mutated\n")

            status = install_plugins.main(
                ["--restore", str(backup_path), str(config_path)]
            )

            self.assertEqual(0, status)
            self.assertEqual(b"original\r\n", config_path.read_bytes())
            self.assertFalse(backup_path.exists())

    def test_invalid_cli_json_is_nonzero_and_restores_config(self) -> None:
        codex = "codex"
        marketplace_list = [codex, "plugin", "marketplace", "list", "--json"]
        plugin_list = [codex, "plugin", "list", "--json"]
        original = b"# original\r\n"
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "config.toml"
            config_path.write_bytes(original)
            runner = AlwaysMutatingRunner(
                config_path,
                {
                    tuple(marketplace_list): subprocess.CompletedProcess(
                        marketplace_list, 0, "{broken", ""
                    ),
                    tuple(plugin_list): completed(plugin_list, {"installed": []}),
                },
            )

            status = install_plugins.reconcile(
                config_path=config_path,
                runner=runner,
                codex_path=codex,
            )

            self.assertEqual(1, status)
            self.assertEqual(original, config_path.read_bytes())

    def test_main_reads_codex_home_config(self) -> None:
        codex = "codex"
        marketplace_list = [codex, "plugin", "marketplace", "list", "--json"]
        plugin_list = [codex, "plugin", "list", "--json"]
        runner = RecordingRunner(
            {
                tuple(marketplace_list): completed(
                    marketplace_list, {"marketplaces": []}
                ),
                tuple(plugin_list): completed(plugin_list, {"installed": []}),
            }
        )
        with tempfile.TemporaryDirectory() as directory:
            dotfiles_root = Path(directory) / "dotfiles"
            tools_dir = dotfiles_root / "codex-tools"
            home_config = dotfiles_root / "codex" / "config.toml"
            tools_dir.mkdir(parents=True)
            home_config.parent.mkdir()
            home_config.write_text("", encoding="utf-8")
            fake_installer = tools_dir / "install_plugins.py"
            fake_installer.write_text("", encoding="utf-8")

            with patch.object(
                install_plugins, "__file__", str(fake_installer)
            ), patch.object(
                install_plugins, "SubprocessRunner", return_value=runner
            ), patch.object(
                install_plugins.shutil, "which", return_value=codex
            ):
                status = install_plugins.main([])

        self.assertEqual(0, status)
        self.assertEqual([marketplace_list, plugin_list], runner.calls)


if __name__ == "__main__":
    unittest.main()
