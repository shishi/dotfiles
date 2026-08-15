# Bootstrap failure diagnostics

## Change

`bootstrap()` now writes `migrate-home: bootstrap failed: <error>` to stderr
when an `OSError` aborts bootstrap. It prints only the exception message; it
does not print copied runtime contents, rollback data, or other secrets.

## TDD evidence

- RED: `python -m unittest codex-tools/tests/test_migrate_home.py -k bootstrap_copy_failure_prints_error_diagnostic` failed because stderr was empty.
- GREEN: the same test passed after the minimal diagnostic output change.

## Verification

- `python -m unittest discover -s codex-tools/tests -p 'test_*.py'` — 84 tests passed.
- All four `codex-tools/tests/*.test.sh` wrapper and integration tests passed.
- `bash -n` passed for every `codex-tools/**/*.sh` script.
- `git diff --check` passed.
