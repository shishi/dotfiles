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

`dotfiles/codex` remains the visible source of truth for the linked `~/.codex` home, and the default-deny `.gitignore` boundary over it is unchanged. `setup.sh` creates each link with `ln -sfn` — `-n` because `ln -sf` would follow an existing directory symlink and link inside it — and decides per target:

* Missing link source: report and do nothing, rather than plant a link that dangles from the start.
* Missing target: link.
* Symlink that already resolves into this checkout: do nothing at all. Re-running touches no link, so a machine that cannot create symlinks does not lose a working one to `ln -f`.
* Dangling symlink: relink, and report the discarded target, because that value is the only record of where it pointed.
* Anything else — a symlink into a different checkout, one that resolves nowhere, or a real directory: report the path and leave it alone. Each holds runtime the repository does not carry (`auth.json` and sessions for Codex, credentials and session history for Claude Code, `skills/.system/` for the skills link), and the report says the runtime has to move before the path can be relinked. It does not spell out how; the procedure depends on what is actually in that home, and a fixed recipe printed at runtime went stale faster than it was read.

Each decision compares resolved real paths, not link text. That is why "cannot resolve" is its own case on both sides: an unresolvable source and an unresolvable target would otherwise compare equal and the run would do nothing while both are broken, and a link whose target could not be inspected would fall through to `ln` and be replaced.

`~/.claude` goes through the same function — it is a home whose ignored runtime holds `projects/`, `sessions/`, `history.jsonl`, `plugins/` and the agent-memory link — which is why the function is named `link_agent_home` rather than for one of its callers. Editor configuration uses a separate one that does destroy a real directory, since the repository is its only copy.

The bind-mount case stays outside both. A `~/.claude` provided by a devcontainer bind mount is a real path, and moving it aside acts on the mount source rather than on a copy. That check runs first, only when `~/.claude` is not a symlink, and reports on its own. It is deliberately incomplete: it does not compare the mount source against `dotfiles/claude`, and the `/proc/mounts` fallback misses a `$HOME` containing regular-expression metacharacters or a mount point containing a space. `~/.codex` carries no equivalent check because no container definition here mounts it — an observation about the current setup, not something this repository enforces.

`setup.sh` has no `set -e` and ends with an unconditional `echo`, so its exit status cannot carry these outcomes; each skipped or failed path is reported as one line naming the path, and a failed `ln` names Developer Mode and elevation as the Windows cause.

Adopting a machine that already has a real `~/.codex` is a manual job with no tool behind it. The shape is: move the directory aside under a name that does not already exist — `mv` into an existing directory nests instead of failing — re-run, and move the runtime back. What must not move back is whatever `git ls-files` reports as tracked at that home's top level, because moving those over turns machine-specific content into uncommitted changes; skipping the runtime entirely leaves a working but signed-out home. The whole directory has to move aside, not part of it, or the link is never created on the next run. The run does not print these steps: it names the path it skipped and that runtime is involved, and this is where the steps live.

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

`tests/setup-home-links.sh` runs the real `setup.sh` against a fixture `HOME`. For each of the three agent homes it asserts the fresh link, that a second run leaves it intact, that a pre-existing real directory keeps its contents, that a link into another checkout is left alone, that a dangling link is repaired and the discarded target recorded, and that every skip names the path rather than passing in silence. It also covers the editor-config links, the per-file nushell links, a missing link source, and that `setup.sh` no longer references `codex-tools`. The bind-mount branch is checked statically, by line number, to confirm it still precedes the shared function.

The self-link case — that an already-correct link is not removed and recreated — is covered for `~/.claude` only, by planting a relative link and asserting its text survives the run. Git Bash preserves a relative link's text verbatim while normalising an absolute one, so the same trick needs a relative form that `~/.codex` is not planted with. Inode comparison is not used; it is not established as reliable here. The suite exports `MSYS=winsymlinks:nativestrict` itself, because the links it plants as preconditions would otherwise become directory copies under Git Bash and exercise the wrong branch. `tests/setup-windows-symlinks.sh` covers that requirement for the script. Nothing asserts the ignore boundary automatically: `.gitignore` enforces it directly, and gitleaks in the review gate covers the secret case.

## Pros and Cons of the Options

### Create the two links inline in setup.sh and delete codex-tools

* Good, because the surviving behaviour is a handful of guarded `ln` calls that read like the rest of `setup.sh`.
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
