# App marketplace reconciliation report

- Root cause: Codex appends a runtime `openai-bundled` marketplace with a
  `local` source to the managed configuration.
- Fix: validation accepts a `local` source only for names in
  `APP_SUPPLIED_MARKETPLACES`; all other marketplaces remain `git`-only.
- Tests: `python -m unittest codex-tools.tests.test_install_plugins` (18 tests)
  and `git diff --check` pass.
- Review: Claude review could not authenticate (expired OAuth). The Codex
  fallback review timed out twice. An independent self-review of the changed
  validation and regression tests found no defect.
- Scope: `codex/config.toml` was already modified by runtime behavior and was
  intentionally left untouched. No installed plugins were changed.
