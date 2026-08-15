# Git Marketplace Runtime Metadata Report

## Root cause

Codex records `last_updated` and `last_revision` in managed Git marketplace
tables at runtime. The installer required an exact two-key table and therefore
rejected otherwise valid desired configuration before invoking the CLI.

## Fix

The installer permits exactly those two runtime metadata keys for non-app Git
marketplaces, validates that `source_type` and `source` are still present and
valid, rejects all other keys, and passes a source-only desired mapping into
reconciliation.

## TDD evidence

- RED: `test_git_marketplace_runtime_metadata_is_ignored` failed with `0 != 1`
  before the implementation change.
- GREEN: `python -m unittest tests.test_install_plugins` passed.
- Regression coverage keeps unknown metadata, missing/invalid required fields,
  and non-Git non-app marketplaces rejected without calling the CLI.

## Verification

- `python -m unittest discover -s tests` passed.
- `git diff --check` passed.
- Claude native review completed with no reported findings (one iteration).

## Scope

No real plugin operation was run. Existing `codex/config.toml` and
`task-app-marketplace-report.md` worktree changes were left untouched.
