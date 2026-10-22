---
name: git-commit
description: "承認された変更を意味のある単位で stage・commit し、変更理由を示す Conventional Commit を作成します。commit の依頼や作業の区切りで使い、push の許可は含みません。"
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git commit:*), Bash(git restore:*), Bash(git show:*)
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

- Write the exact commit message with the file editing tool, read it back, and pass it with
  `git commit -F` and that file's absolute path. Do not embed multiline prose in shell code.

- **Breaking changes**: only `feat!:` / `fix!:` may carry `!`. If a
  refactor/style/docs/chore changed behavior, it is misclassified —
  recategorize as feat or fix.
- **Message philosophy (t-wada)**: code describes HOW, tests describe WHAT,
  commit log describes **WHY**, code comments describe WHY NOT. The body
  explains reasoning and motivation — what problem, why now, why this
  approach over alternatives — not a restatement of the diff. Apply writing-prose's
  publication rules to the message: include reader-relevant reasons, not private
  machine identifiers, local paths, or agent working notes moved out of documents.
- Subject: imperative mood, under 50 characters.
- One logical unit per commit. Use `git add -p <file>` when a file mixes
  unrelated changes, and split into multiple commits, one at a time.

## Checklist before committing

- [ ] Staged changes serve a single purpose (verify with `git diff --cached`)
- [ ] Type matches the nature of the change (`refactor:` has no behavior change)
- [ ] Body answers: what problem, why now, why this approach
- [ ] Breaking changes are marked `feat!:` / `fix!:`
- [ ] If the project has a CI-skip convention and this commit touches
      no code, the subject carries the project's skip marker
