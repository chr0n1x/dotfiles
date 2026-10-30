---
name: rebase
description: Rebase an open PR branch onto its current base in an isolated worktree, validate it, and optionally publish rewritten history after explicit force-push confirmation.
user-invocable: true
argument-hint: "[PR number or branch]"
allowed-tools: Bash(git:*), Bash(gh:*), Bash(mkdir:*), Bash(tmux:*), Read, Write
---

# Rebase a PR branch

Rebase an existing PR branch onto its current base in a dedicated worktree.
The worktree is the safety boundary: never rebase the user's current checkout.
Load the `worktree`, `gh-stack`, and `commit-push` skills before their
corresponding steps. This command coordinates them; it does not replace their
rules.

## 1. Resolve and inspect

- Resolve the PR number or branch, repository, head owner/repository, head
  branch, base branch, head SHA, and PR state. For a PR, use `gh pr view`.
- Determine the push remote from the PR head owner, not from the base repo or
  the branch's configured upstream. Match the PR head repository to
  `git remote -v` (for example, a fork PR often pushes to `origin` while the
  base repository is `upstream`). Confirm the chosen remote by checking that
  `git ls-remote --heads REMOTE HEAD_BRANCH` returns the PR's current head SHA.
  If no remote matches, or the remote SHA differs, stop and inspect before
  pushing. Never infer the push remote from `branch.*.remote` alone.
- Read repo instructions and validation guidance. Check `git remote -v`,
  `git worktree list`, and `git status --short` in the source checkout.
- Check `gh stack --help` and `gh stack view --json` from the target branch
  worktree when available. Import remote stack metadata with the `gh-stack`
  workflow when membership is possible. If stacked, follow the stack rebase
  and submit procedures; do not use a standalone force-push.
- Refuse closed/merged PRs unless the user explicitly asks to restore them.
- Select a unique path under `~/.worktrees/<repo>/rebase-<pr-or-branch>`.
  If it exists, inspect it and ask before reuse or choosing another path.
- Do not touch uncommitted source state. Create a worktree from the PR head
  branch, or fetch and check out the exact head into a new branch there. Never
  switch branches in the source checkout.

## 2. Confirm the local rebase

Before rebasing, show the target branch, base ref and SHA, current head SHA,
worktree path, and expected validation. Ask for yes/no confirmation. If the
rebase is clean, this confirmation authorizes the complete requested workflow,
including any required commits, pushes, and stack syncs, subject to the remote,
branch, and stack checks below. This overrides the separate confirmation gates
in `commit-push` and `gh-stack` for actions within this rebase workflow. Do not
ask again for those already-authorized actions.

If the rebase has conflicts, stop and show the conflicted paths and proposed
resolutions. Review them with the user. After the user approves the resolutions,
show the resulting rebase plan and ask for confirmation to proceed. That
confirmation authorizes resolving those conflicts and the complete requested
workflow, including any required commits, pushes, and stack syncs, subject to the
remote, branch, and stack checks below. This overrides the separate confirmation
gates in `commit-push` and `gh-stack` for actions within this rebase workflow.
Do not ask again for those authorized actions. Never discard conflicting changes.
Run the repo-documented checks for changed modules and `git diff --check`.

For a standalone PR, compare the final diff to the base and inspect the new
commit list. For a stack, verify the branch chain and `needsRebase` state with
`gh-stack`.

## 3. Publish rewritten history (optional)

Before publishing, report the rebased head SHA, selected head remote and branch,
the remote branch SHA, PR state/base/head, validation results, and whether the
remote is an ancestor of the local head. Recheck that the selected remote still
contains the PR's previously reported head SHA immediately before publishing.

For a clean rebase, the confirmation in Step 2 authorizes the requested publish
and any required stack sync. Use the `commit-push` workflow for normal pushes and
`gh-stack` for stack syncs; their confirmation gates are satisfied by that
Step 2 confirmation. Do not ask again for an action it explicitly covered.

If rebasing rewrote commits already on the remote, publish only if rewritten
history was explicitly part of the user's request or the Step 2 confirmation
named the exact commit SHA, canonical remote, branch, and `--force-with-lease`
operation. That specific authorization overrides the separate publish gate in
`commit-push`; do not ask again. Never use plain `--force`. Recheck the remote
SHA immediately before pushing. If it changed, stop and inspect the new commits;
do not retry blindly. For stacks, use only the `gh-stack` sync/submit procedure,
never direct force-push.

## 4. Cleanup

Keep the worktree and branch by default so the user can inspect or continue.
Ask before removing the worktree, deleting its branch, or closing its tmux
window. Never remove a pre-existing worktree or branch.
