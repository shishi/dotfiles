---
name: git-commit
description: "承認された変更を意味のある単位で stage・commit し、変更理由を示す Conventional Commit を作成します。commit の依頼や作業の区切りで使い、push の許可は含みません。"
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git commit:*), Bash(git restore:*), Bash(git show:*), Bash(git apply:*), Bash(git rev-parse:*)
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
  approach over alternatives — not a restatement of the diff. State the problem and
  the reason at the level a later reader of the history needs to judge the change.
  Leave out the record of how the change was verified — trial counts, per-run
  results, the models and conditions compared, the steps of the investigation —
  which stays in untracked working notes. Apply writing-prose's
  publication rules to the message: include reader-relevant reasons, not private
  machine identifiers, local paths, or agent working notes moved out of documents.
- Subject: imperative mood, under 50 characters.
- One logical unit per commit, committed one at a time. When a file mixes
  unrelated changes, stage one unit's hunks without an interactive prompt
  (`git add -p` waits for answers the tools cannot type): save `git diff <file>`
  to a patch file outside the repository (under `${TMPDIR:-/tmp}`), delete the
  other units' hunks with the file editing tool, and run
  `git apply --cached <patch>`. When one hunk holds both your change and someone
  else's, deleting lines from that hunk can reorder them, so edit the index
  through a copy instead. From the repository root (`git rev-parse
  --show-toplevel`) with root-relative paths, write the current index version
  (`git show :<path>`) to a file outside the repository, copy it, and change
  only your lines in the copy, taking added lines from `git diff <path>` (which
  has passed the file's clean filter). Make a patch with `diff -u --label
  a/<path> --label b/<path> <index copy> <your copy>`, then run `git apply
  --cached --check` and `git apply --cached`. Because the patch is made from
  the current index, it keeps whatever others have staged; if the index changed
  in between, make it again.
  A commit takes everything staged, so never commit while the index holds
  changes you did not make; check `git diff --cached` before staging and before
  committing. If others' changes are staged, wait until they are committed. If
  yours are staged alongside theirs, take yours back out the same way (a copy
  of the current index with only your lines restored), confirm only their
  changes remain, and wait. Then stage yours again from the new index.

## Checklist before committing

- [ ] Staged changes serve a single purpose (verify with `git diff --cached`)
- [ ] Type matches the nature of the change (`refactor:` has no behavior change)
- [ ] Body answers: what problem, why now, why this approach
- [ ] Breaking changes are marked `feat!:` / `fix!:`
- [ ] If the project has a CI-skip convention and this commit touches
      no code, the subject carries the project's skip marker
