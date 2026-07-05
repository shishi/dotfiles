---
name: git-commit
description: "Stage meaningful diffs and create Conventional Commits with WHY-focused messages"
---

# Git Commit

Create Conventional Commits (1.0.0) with WHY-focused messages.

## Context

Inspect the repository state first:

```bash
git status --short
git diff --stat            # unstaged
git diff --cached --stat   # staged
git log --oneline -10      # style reference
```

## Rules beyond what the Conventional Commits spec says

- **Breaking changes**: only `feat!:` / `fix!:` may carry `!`. If a
  refactor/style/docs/chore changed behavior, it is misclassified —
  recategorize as feat or fix.
- **Message philosophy (t-wada)**: code describes HOW, tests describe WHAT,
  commit log describes **WHY**, code comments describe WHY NOT. The body
  explains reasoning and motivation — what problem, why now, why this
  approach over alternatives — not a restatement of the diff.
- Subject: imperative mood, under 50 characters.
- One logical unit per commit. Use `git add -p <file>` when a file mixes
  unrelated changes, and split into multiple commits, one at a time.

## Checklist before committing

- [ ] Staged changes serve a single purpose (verify with `git diff --cached`)
- [ ] Type matches the nature of the change (`refactor:` has no behavior change)
- [ ] Body answers: what problem, why now, why this approach
- [ ] Breaking changes are marked `feat!:` / `fix!:`
