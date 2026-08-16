# Declarative Codex Home Design

Status: superseded by `docs/ADR/20260816-180256-link-codex-home-from-setup-sh.md`. Retained as history. The linked home itself is current — `~/.codex` and `~/.agents/skills` resolve into `dotfiles/codex`, and `setup.sh` creates both links with `ln -sfn`. What no longer exists: the `codex-tools` directory, the plugin reconciler, and the migration, installation, and verification scripts described below. The setup guarantees in "Setup and Migration" are gone with them — `setup.sh` takes no lock, checks no platform capability, verifies nothing after linking, and rolls nothing back. A failed link is reported on one line and the run still exits 0, so the acceptance criterion "setup returns nonzero when plugin restoration or link creation fails" does not hold either: that one line is the only signal. The "Testing" list below describes the deleted suites, not present coverage — what remains is enumerated in the ADR's Confirmation section, including the one claim it leaves uncovered. The tracked `config.toml` still carries whatever plugin and marketplace state Codex writes, but no step converges installations toward it — plugin selection follows the signed-in account. Adopting a machine that already has a real `~/.codex` is a manual job with no tool behind it.

## Goal

Make `dotfiles/codex` the source of truth for durable Codex configuration. Link the whole directory to `~/.codex`, select plugins declaratively, and rebuild missing plugin installations on a new machine.

## Scope

The repository manages:

- `AGENTS.md`
- `config.toml`, including plugin and marketplace desired state
- custom agents and rules
- hooks and their tests
- personal skills
- plugin marketplace definitions and enabled plugin IDs
- setup, migration, installation, and verification scripts

Codex writes configuration changes directly to the tracked `config.toml`, as Claude writes tracked `settings.json`. Git ignores authentication data, sessions, caches, logs, databases, temporary files, downloaded plugin bundles, and other files not explicitly allowlisted.

## Source of Truth

`dotfiles/codex` is authoritative. `~/.codex` links to that directory. `~/.agents/skills` separately links to `dotfiles/codex/skills` because Codex discovers personal skills from `~/.agents/skills`.

The root `.gitignore` ignores every path below `codex/` unless the repository explicitly allowlists it. It ignores Codex's generated `skills/.system` directory even though it allowlists personal skills. This rule protects unknown runtime files added by future Codex versions. Tests reject tracked credentials and runtime state.

## Plugin Model

`codex/config.toml` is the only source of plugin desired state. External `[marketplaces.NAME]` tables record portable Git sources. Each `[plugins."PLUGIN@MARKETPLACE"]` table records `enabled = true` or `enabled = false`. Local app-managed marketplace paths may appear in live runtime configuration but are not tracked installation sources.

`codex/install-plugins.sh` performs reconciliation:

1. Exit successfully when the Codex CLI is unavailable.
2. Validate and read marketplace and plugin tables from `config.toml`.
3. Save the exact `config.toml` bytes to a temporary file on the same filesystem.
4. Add only a missing external marketplace that is required by an enabled plugin, using its tracked Git source. A tracked marketplace needed only by disabled or unmanaged plugins is not added.
5. After those additions, read installed plugins with `codex plugin list --json`.
6. Install each enabled but missing plugin with `codex plugin add`.
7. Remove each installed plugin whose tracked entry has `enabled = false`, except plugins from the removal-protected marketplaces named below.
8. Restore the saved `config.toml` bytes with an atomic replacement after success or failure. This preserves disabled sentinels and prevents CLI-generated metadata from changing the source of truth.
9. Skip already converged entries. Plugin IDs absent from `config.toml` are unmanaged and remain unchanged.
10. Reject duplicate plugin IDs, malformed TOML, source mismatches, and enabled source-backed plugins whose marketplace has no tracked source. Marketplace values must be tables containing exactly string `source_type = "git"` and string `source`; plugin values must be tables containing exactly one Boolean `enabled`. Scalars, extra keys, and other value shapes are rejected before invoking the CLI. App-supplied plugins and disabled-only removal sentinels may omit a marketplace source because the installer never installs them.
11. Return nonzero when listing, marketplace reconciliation, plugin installation, plugin removal, or configuration restoration fails.

`openai-bundled`, `openai-primary-runtime`, and `openai-api-curated` are app-supplied marketplaces. Their local marketplace sources are runtime state and are not tracked. The installer reports a warning and returns success when one of their enabled plugins is unavailable, and it never invents a source or installs them from another marketplace. `openai-bundled` and `openai-primary-runtime` are removal-protected. `openai-api-curated` is not removal-protected: an enabled entry such as `codex-security@openai-api-curated` remains app-supplied, while a disabled entry may be removed. Other installed plugins may report a local cache source at runtime; that alone does not classify their marketplace as app-supplied.

The configuration keeps `superpowers@superpowers-marketplace` enabled and records `superpowers@openai-api-curated` as a disabled-only removal sentinel without a marketplace source table. Reconciliation may remove this installed plugin even though the CLI reports its cached source as local. This eliminates fourteen duplicated skill names while retaining upstream Superpowers 6.3.0. A later tidy may delete the disabled table after all managed environments have converged.

## Skill Model

`codex/skills` contains every personal skill. Consolidation uses these sources:

- keep repository `adr`, `logging`, and `tidying`; their active copies are identical;
- keep repository `codex-review`; it contains the current Codex sandbox and review fallback guidance;
- keep repository `git-commit`; it omits Claude-only `allowed-tools` metadata;
- keep repository `missing-tools`; it contains the current Windows resolution path;
- keep repository `tdd` and `claude-review`, which are absent from the active personal directory;
- import active personal `compact-prep` and `memory-consolidate` to preserve current behavior.

Tests compare skill directory names, require one `SKILL.md` per skill, and reject a separate real `~/.agents/skills` directory after setup.

## Setup and Migration

Fresh setup creates these links:

- `~/.codex` -> `dotfiles/codex`
- `~/.agents/skills` -> `dotfiles/codex/skills`

Before creating links, setup acquires an atomic `mkdir` lock, creates `~/.agents`, verifies that the platform can create real directory symlinks, and verifies the result rather than trusting a zero exit status. An existing link is accepted only when both paths resolve successfully to the same target; resolution failure is a refusal, not an idempotent success. On Git Bash/MSYS, setup requires native symlink support through Developer Mode or elevation. If creation or final verification fails, setup cleans up links created by that attempt in reverse order. Before each removal it checks both link ownership and the raw `readlink` target, continues best-effort after an individual cleanup failure, and reports the original failure plus any incomplete rollback diagnostics.

Existing real directories require migration. Migration must:

1. Refuse to run while Codex processes are using the active home. The user runs migration after closing Codex.
2. Resolve and verify every source and destination path.
3. Inventory all entries, classify managed and runtime paths, and fail on an unclassified path. The repository copy of every managed path, including `config.toml`, remains authoritative.
4. Preflight every destination and fail on a content collision.
5. Copy the complete existing `~/.codex` and `~/.agents/skills` trees to a timestamped backup rooted outside the repository.
6. Verify the backup by relative path and path type. Verify size and SHA-256 for regular files. Verify link type and target without following symbolic links or junctions.
7. Copy runtime-only entries from the verified backup into ignored repository paths without overwriting existing data. Treat `skills/.system` as nested runtime only when its `skills` parent is a real directory; never follow it through a symbolic link or junction.
8. Record every repository runtime path created by migration in a transaction journal. Verify the copied paths, then re-check for Codex processes before mutating either live directory. Do not copy the old `config.toml`, managed hooks, or personal skills into their authoritative repository paths.
9. Atomically rename each live directory into a commit-time snapshot inside the backup; do not delete it. Create and verify both links only after the snapshots exist. If snapshotting, link creation, or verification fails, remove only links created by migration, restore the live directories from their snapshots, and clean journaled repository paths in reverse order. Rollback is best-effort across all paths and reports every failed action. Junction creation rejects `cmd.exe` metacharacters in both destination and target before launching `cmd.exe`.
10. Commit the filesystem migration after both links resolve to their expected targets. Run plugin reconciliation as a separate, retryable post-migration step. A plugin failure returns nonzero but does not undo the verified links; the installer restores `config.toml` byte for byte.
11. Print the backup location, verification result, plugin reconciliation result, and exact recovery steps. Before the filesystem commit, a failure prints the exact `migrate-home.sh --restore BACKUP_DIR` command. After the explicit filesystem commit, a plugin failure prints only the retry command and never suggests undoing verified links. Keep the backup until the user removes it explicitly.

`migrate-home.sh --restore BACKUP_DIR` accepts only a real backup directory containing real `codex` and `agents-skills` directories. It copies both to fresh staging paths, verifies them without following links or junctions, re-checks for Codex processes, and preserves any current live paths as timestamped pre-restore entries. It then swaps both staged trees into place using renames. A partial two-path swap triggers best-effort rollback to the pre-restore paths, while the supplied backup remains unchanged.

The normal setup script remains non-destructive. It does not replace an existing real directory automatically. The migration and plugin wrappers select the first available `python3` or `python` that is Python 3.11 or newer, falling back when the first candidate is too old. Migration has success, collision, copy/verification failure, process-race, partial-snapshot, partial-link, restore-swap, and rollback tests against temporary directories.

## Configuration Boundary

`config.toml` tracks durable non-secret Codex settings: root model and reasoning preferences, personality and developer instructions, sandbox and approval policy, project trust, Windows sandbox preference, shell environment policy, desktop preferences, plugin selections, portable external marketplace sources, hook trust hashes, and explicit computer-use application allowances. Machine-specific durable choices are expected dotfiles diffs and remain reviewable.

Before migration, a tested key-classification fixture compares the live and repository configurations. Current live durable preferences are adopted, project trust entries are merged, and intentional repository policy remains authoritative for `developer_instructions`, `personality`, `approvals_reviewer`, and disabled native memories. App-generated MCP command/env tables, the current versioned runtime `notify` command, native pipe identifiers, installation and executable paths, app version data, marketplace timestamps/revisions, and app-supplied local marketplace paths are excluded and may be regenerated locally after setup.

Authentication values, connector tokens, API keys, native pipe identifiers, installation IDs, sessions, database state, and the excluded generated configuration keys stay untracked. Tests reject known secret key names, credential-shaped values, and forbidden generated keys in tracked configuration.

## Security Boundaries

Ignored files still live inside the dotfiles working tree. Therefore:

- never use `git add -f` below `codex/` without inspecting the exact path;
- never run `git clean -x` against the repository;
- reject tracked `auth.json`, session data, SQLite files, caches, logs, and plugin downloads;
- preserve a recoverable backup during migration;
- keep marketplace credentials and connector tokens out of tracked configuration.

## Testing

Implementation follows Red-Green-Refactor. Tests cover:

1. `.gitignore` defaults to ignoring new `codex/` runtime files and allowlists only managed paths.
2. sensitive and runtime files are not tracked;
3. Superpowers has one enabled provider;
4. enabled plugin IDs are unique;
5. the installer skips unavailable tooling, installed enabled plugins, and disabled plugins that are already absent;
6. the installer adds only a missing marketplace required by an enabled external plugin, then lists plugins before reconciling them;
7. malformed TOML, strict value-shape rejection, marketplace/plugin list failure, source mismatch, missing app-supplied plugins, removal protection, disabled-only sentinels, install failures, and removal failures have defined results;
8. installer failures propagate through top-level setup as a nonzero status;
9. setup creates and verifies both links on Unix and Git Bash/MSYS test fixtures, serializes attempts with its lock, refuses link-resolution errors, and diagnoses ownership-aware reverse cleanup failures;
10. setup refuses to replace existing real directories;
11. migration verifies regular files, symbolic links, junctions, and a real-parent `skills/.system` without following external targets; it re-checks processes before mutation and rolls back commit-time live snapshots and journaled repository paths after partial failures;
12. migration changes both enabled Superpowers providers into only the upstream provider;
13. two consecutive machine fixtures retain the disabled curated-Superpowers sentinel after reconciliation;
14. installer success and failure leave tracked `config.toml` byte-for-byte unchanged;
15. a live/repository key-classification fixture proves which durable settings are adopted, merged, repository-owned, or rejected;
16. tracked configuration contains no secrets or forbidden generated keys;
17. restore rejects unsafe backups, stages and verifies both trees, re-checks processes, preserves pre-restore live paths, rolls back a partial two-path swap, and retains the backup;
18. pre-commit failures print the exact restore command, while post-commit plugin failures print retry-only recovery;
19. both wrappers enforce Python 3.11 or newer with candidate fallback;
20. all personal skills reside in `codex/skills`.

## Acceptance Criteria

- `dotfiles/codex` contains every durable Codex setting and personal skill.
- A fresh machine can restore external enabled plugins from tracked configuration.
- `~/.codex` and `~/.agents/skills` resolve to the repository.
- Codex runtime state remains untracked.
- setup returns nonzero when plugin restoration or link creation fails.
- migration can restore the original two live directories after an injected partial failure.
- only one Superpowers plugin supplies its fourteen workflow skills.
- all new and existing tests pass.
- a new review agent reports no blocking findings.
