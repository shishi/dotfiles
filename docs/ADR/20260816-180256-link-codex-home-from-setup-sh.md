# Link the Codex Home from setup.sh Without Separate Tooling

| | |
|---|---|
| **Status** | accepted |
| **Date** | 2026-08-16 |
| **Decision-makers** | shishi |
| **Consulted** | Live link state of this machine; maintainer's observation of Codex plugin storage |
| **Informed** | dotfiles maintainers |

Supersedes [_20260813-224935-use-linked-declarative-codex-home.md](_20260813-224935-use-linked-declarative-codex-home.md).

## Context and Problem Statement

The linked declarative Codex home is in place: `~/.codex` and `~/.agents/skills` resolve into `dotfiles/codex`. The tooling that established it shipped as `dotfiles/codex-tools` — a one-shot full-snapshot bootstrap, a worktree promotion helper, a plugin reconciler, and a link helper, together roughly 6,100 lines of Python, Bash wrappers, and their tests. That bootstrap and promotion pair refuses to run against an already-linked home, so it has no second use; the reconciler maintains a desired state that Codex keeps with the signed-in account; and the link helper reaches for Python only to implement its own rollback. Nothing else in `setup.sh` needs an interpreter.

## Decision Drivers

* Keep the linked declarative Codex home; only its tooling is in question.
* Keep `setup.sh` dependency-free — Bash and Git only, as every other link in it is.
* Delete tooling whose one-shot job is finished instead of maintaining it unused.
* Do not maintain a local desired state that the Codex account already restores.
* Keep setup non-destructive toward a real `~/.codex` holding credentials and sessions.

## Considered Options

1. Create the two links inline in `setup.sh` and delete `codex-tools` entirely.
2. Keep `codex-tools` as a directory but rewrite every tool in Bash.
3. Keep `codex-tools` as it is.

## Decision Outcome

**Chosen option**: "Create the two links inline in `setup.sh` and delete `codex-tools` entirely", because the only tool still needed on a fresh machine is two `ln` calls, and every other reason to keep the directory has expired.

`dotfiles/codex` remains the visible source of truth for the linked `~/.codex` home, and the default-deny `.gitignore` boundary over it is unchanged. `setup.sh` creates both links with `ln -sfn` — `-n` because `ln -sf` would follow an existing directory symlink and link inside it — and decides per target:

* Missing link source: report and do nothing, rather than plant a link that dangles from the start.
* Missing target: link.
* Symlink that already resolves into this checkout: do nothing at all. Re-running touches no link, so a machine that cannot create symlinks does not lose a working one to `ln -f`.
* Dangling symlink: relink, and report the discarded target, because that value is the only record of where it pointed.
* Symlink resolving into a different checkout or worktree: report where it points and leave it alone. Repointing it would leave Codex signed out, and every session and credential it then writes would land in this checkout while the old ones stay behind. The remedy is per target, because the one for `~/.codex` names the runtime entries to move first and that same instruction against `~/.agents/skills` would put credentials into `codex/skills/`, which the ignore rule re-includes as tracked.
* Symlink that resolves to no directory for any other reason, such as a missing traversal permission: report and leave alone, since it cannot be classified as either of the two cases above.
* Real directory: report and leave alone, because it holds `auth.json` and sessions.

Each decision compares resolved real paths, not link text. The two "cannot resolve" cases are what make that comparison sound rather than extra hardening: with no missing-source case, an unresolvable source and an unresolvable target compare equal and the run silently does nothing while both are broken, and with no unresolvable-target case, a link whose target could not be inspected falls through to `ln` and gets replaced — the outcome the previous case exists to prevent. Checking a source before linking is not new here — the agent-memory block reports and skips when its clone is unavailable. The blocks that skip the check are the ones that decide nothing from a resolved path.

The refusal to repoint carries over the one guard the deleted link helper had that inline `ln` calls lack. `~/.claude` faces the same hazard and keeps its unconditional relink; changing it is separate work, not part of moving the Codex helper.

`setup.sh` has no `set -e` and ends with an unconditional `echo`, so its exit status cannot carry these outcomes; each skipped or failed path is reported as one line naming the path, and a failed `ln` names Developer Mode and elevation as the Windows cause.

Adopting a machine that already has a real `~/.codex` is a manual, two-part job with no tool behind it. Stop Codex, move the directory aside under a name that does not already exist — `mv` into an existing directory nests instead of failing — and run `setup.sh` to create the link. Then copy from the backup only what the ignore rule denies by default: `auth.json`, `sessions/`, `plugins/`, `sqlite/`, `browser/` and the like. `AGENTS.md`, `config.toml`, `agents/`, `rules/`, `skills/` except `skills/.system/`, `hooks/`, and `hooks.json` are re-included and tracked, so copying them over turns machine-specific content into uncommitted changes. Skipping the runtime copy altogether leaves a working but signed-out home.

Setup performs no Codex plugin reconciliation. Codex keeps plugin selection with the signed-in account and restores it after sign-in, unlike Claude Code, whose plugins are installed from tracked `settings.json`; that difference is the maintainer's observation of the app rather than a re-verified CLI interface. The tracked `config.toml` still carries whatever plugin and marketplace state the app writes into the linked home, but no step converges installations toward it.

No test asserts the contents of the tracked `config.toml`, and none classifies its keys. Codex owns that file and rewrites it inside the linked home, so pinning its model, plugin table, marketplaces, or trust entries reports drift rather than defects. The boundary that keeps credentials and sessions out of version control is the default-deny `.gitignore` itself, and secrets are caught by gitleaks over every changed file in the review gate — a broader ruleset than a hand-written one, and one that needs no credential-shaped literal stored in the repository in order to test itself.

### Consequences

**Positive:**

* `setup.sh` needs no Python and no external helper, and one file describes home linking for both Claude Code and Codex.
* The Windows junction, ReadOnly-attribute, and no-replace-rename handling that the deleted tools carried is no longer a maintenance surface.
* Plugin state has one home — the account — instead of an account plus a tracked desired state that can disagree with it.

**Negative:**

* There is no automated rollback when one link succeeds and the other fails. `setup.sh` reports the failing path and continues, and the operator inspects it and re-runs; a re-run is safe because each target is decided independently.
* A failed link does not fail the run. `setup.sh` still exits 0 and prints `please reload shell`, so the reported line is the only signal, and on Windows a first run without Developer Mode leaves no link at all.
* A signed-out fresh machine has no local plugin desired state to converge to, so plugins depend on signing in.
* Adopting an existing real `~/.codex` depends on the operator copying the runtime entries by hand, and copying too much puts machine-specific content into tracked files.
* A key the app newly writes into the tracked `config.toml` reaches a commit unless a human notices it in the diff. No test flags it, and gitleaks only objects when the value looks like a credential.

**Neutral:**

* The superseded bootstrap and tools-split design documents stay under `docs/superpowers/` as history.

### Confirmation

`tests/setup-codex-links.sh` runs the real `setup.sh` against a fixture `HOME` and asserts that both links resolve into the checkout without a reported failure, that a second run leaves them intact, that a pre-existing real `~/.codex` keeps its contents while the skip is reported, that a link into another checkout is left alone with a report naming both its target and the runtime entries to move, that the `~/.agents/skills` remedy does not name those runtime entries, that a dangling link is repaired and the discarded target recorded, that a missing link source produces a report instead of a dangling link, and that `setup.sh` no longer references `codex-tools`. One claim is not covered: nothing fails if the self-link case stops returning early and starts calling `ln` again. Observing that would mean either shimming `ln` on `PATH` or comparing the link's own inode across runs, and neither is established as reliable under Git Bash here — a cost these tests do not otherwise carry. It exports `MSYS=winsymlinks:nativestrict` itself, because the links it plants as preconditions would otherwise become directory copies under Git Bash and exercise the wrong branch. `tests/setup-windows-symlinks.sh` still covers the `winsymlinks:nativestrict` requirement that both links depend on. Nothing asserts the ignore boundary automatically: `.gitignore` enforces it directly, and gitleaks in the review gate covers the secret case.

## Pros and Cons of the Options

### Create the two links inline in setup.sh and delete codex-tools

* Good, because the surviving behaviour is two guarded `ln` calls that read like the rest of `setup.sh`.
* Good, because no interpreter is needed for dotfiles setup.
* Good, because finished one-shot migration code stops being a maintenance surface.
* Bad, because rollback becomes the operator's job: nothing undoes a partial run, and nothing aborts the rest of `setup.sh`.

### Keep codex-tools but rewrite every tool in Bash

* Good, because the rollback semantics could be preserved, which the refusal-to-repoint guard alone does not provide.
* Bad, because it maintains bootstrap and promotion tools that can no longer run.
* Bad, because no-replace rename has no portable Bash equivalent, so the safety it claims would be weaker than the Python it replaces.

### Keep codex-tools as it is

* Good, because nothing has to change and the tests already pass.
* Bad, because `setup.sh` keeps requiring Python 3.11 or newer for two symlinks.
* Bad, because dead one-shot tooling invites the reader to believe it is part of the normal flow.

## More Information

The superseded decision and its full-snapshot bootstrap rationale are in `_20260813-224935-use-linked-declarative-codex-home.md`. The binding designs it referenced, `docs/superpowers/specs/2026-08-15-codex-home-tools-split-design.md` and `docs/superpowers/specs/2026-08-13-declarative-codex-home-design.md`, are retained as historical context only; their `codex-tools` layout and plugin reconciler no longer exist.

Recheck the plugin claim when Codex CLI changes: if plugin selection stops following the account, a fresh machine will need an explicit install step again. The superseded ADR verified `codex plugin list --json`, `codex plugin marketplace add`, and `codex plugin add` against Codex CLI 0.145.0.
