# Use a Linked Declarative Codex Home

| | |
|---|---|
| **Status** | proposed |
| **Date** | 2026-08-13 |
| **Decision-makers** | shishi |
| **Consulted** | Codex official documentation and independent inventory review |
| **Informed** | dotfiles maintainers |

## Context and Problem Statement

The repository copy of `codex/` and the active `~/.codex` directory have diverged. Plugin selection, personal skills, hooks, and instructions no longer have one source of truth, so a fresh machine cannot reproduce the active environment.

## Decision Drivers

* Keep durable Codex configuration in version control.
* Reproduce selected plugins on a fresh machine.
* Match the established Claude directory-link pattern.
* Prevent credentials and runtime state from entering Git.
* Preserve non-destructive setup and recoverable migration.

## Considered Options

1. Link the whole Codex home and allowlist tracked paths.
2. Keep a real Codex home and link managed files individually.
3. Move runtime state elsewhere and generate the Codex home.

## Decision Outcome

**Chosen option**: "Link the whole Codex home and allowlist tracked paths", because it gives `dotfiles/codex` one visible source of truth, matches the existing Claude arrangement, and lets a default-deny `.gitignore` isolate runtime state.

The tracked `config.toml` expresses marketplace sources, plugin selection, and other non-secret settings. An idempotent installer makes plugin installations match its enabled and disabled tables, then restores the tracked file byte for byte so disabled sentinels survive across machines. `openai-bundled`, `openai-primary-runtime`, and `openai-api-curated` are app-supplied and are never installed by the reconciler. The first two are also removal-protected; a disabled curated entry may still be removed even when the CLI reports a local cache source.

### Consequences

**Positive:**

* Configuration changes appear directly in the dotfiles worktree.
* One setup flow restores hooks, skills, instructions, and plugins.
* A default-deny ignore rule protects runtime files added by later Codex versions.
* Marketplace sources and plugin selections have one tracked representation.

**Negative:**

* Ignored credentials and sessions physically reside inside the worktree.
* `git clean -x` can delete ignored Codex state.
* Plugin reconciliation needs a maintained marketplace source map.
* Existing installations need a careful one-time migration.
* Machine-specific app settings can produce reviewable `config.toml` diffs.
* App-generated runtime sections may reappear as working-tree diffs and must fail the configuration guard until excluded before commit.

**Neutral:**

* Downloaded plugin bundles remain local runtime state rather than tracked artifacts.

### Confirmation

Automated tests verify the ignore boundary, live/repository configuration key classification, configuration schema, cross-machine plugin convergence, byte-stable configuration restoration, cross-platform symlink creation, link-aware full-backup migration and journaled rollback, secret and generated-key exclusion, and skill inventory. A new agent reviews the specification and implementation.

## Pros and Cons of the Options

### Link the whole Codex home and allowlist tracked paths

* Good, because all durable configuration has one visible root.
* Good, because it follows the existing Claude setup.
* Good, because the ignore rule can default to denying unknown files.
* Bad, because ignored private state remains below the Git worktree.

### Keep a real Codex home and link managed files individually

* Good, because runtime state stays outside the repository.
* Good, because deleting the repository cannot delete sessions or credentials.
* Bad, because new managed paths require more link logic.
* Bad, because the active directory can drift from the repository.

### Move runtime state elsewhere and generate the Codex home

* Good, because it separates configuration from state.
* Good, because generated files can combine machine-specific values.
* Bad, because Codex exposes `CODEX_HOME` for the whole directory rather than every state path.
* Bad, because nested filesystem links add platform-specific complexity.

## More Information

See `docs/superpowers/specs/2026-08-13-declarative-codex-home-design.md` for implementation requirements.

The design was verified against Codex CLI 0.145.0. At that version, `codex plugin list --json` returns plugin IDs in `installed[].pluginId`, while installation uses `codex plugin marketplace add` and `codex plugin add`. Recheck these interfaces when upgrading the installer. See the [official plugin documentation](https://developers.openai.com/plugins/) for the supported installation flow.
