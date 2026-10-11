---
name: gh-stack
description: Manage a chain of branches based on each other with GitHub Stacks CLI. Use for creating, updating, pushing, submitting, or linking stacked branches and PRs, including when the GitHub UI does not show the stack.
user-invocable: true
argument-hint: "[branches or PRs in bottom-to-top order]"
allowed-tools: Bash(gh stack:*), Bash(gh pr view*), Bash(git:*), Read
---

# gh-stack

Use when several branches form a parent-to-child chain and the user wants a GitHub stack, not just independent PRs. Follow the user's requested operation; do not create PRs or push branches just because they asked to inspect a stack.

**Before any stack mutation, ask for explicit confirmation of the specific operation and target branches/remote, even if the user requested it.** Use the harness's interactive question tool with an explicit two-option `yes`/`no` list (on maki, the `gate` tool does this from three flat strings). Only a `yes` answer counts as confirmation. Mutations: `gh stack init`, `add`, `modify`, `rebase`, `sync`, `push`, `submit`, `link`, `merge`, `unstack`. Read-only inspection needs none. If a failed operation calls for a different mutation, explain and ask again. Commit each change on the right stack branch, following `commit-push` for message conventions; one confirmation covers a stack push (show the commit message, name the operation, branches and remote). Ambiguous text is not approval. Never force-push without explicit authorization.

1. Run `gh stack <subcommand> --help` before using it. Identify the repo, trunk, branch chain, and target remote with `git remote -v`, `git log --oneline --graph --all`, and `gh stack view --json`. Do not assume `origin` is upstream. Check `git status --short` before any operation that can rebase or push; preserve unrelated changes and worktrees.
2. For a new stack, `gh stack init BOTTOM BRANCH2 [MORE]` can adopt existing branches in bottom-to-top order. To extend an **existing** stack, do not re-run `init` with its tracked branches; it fails with `branch "BOTTOM" already exists in a stack`. Check out the current top/parent with `gh stack checkout PARENT`, then run `gh stack add CHILD`. `add` adopts an existing child branch when its history is based on the parent, or creates it if absent; verify with `gh stack view --json`. Do not stage or commit unrelated changes.
3. To publish the stack and create/update its PRs when requested, use `gh stack submit --auto --remote REMOTE` for non-interactive submission (new PRs default to draft; use `--open` only if requested). It pushes branches, sets each PR's base to its parent, and creates/updates the GitHub stack. Confirm PR creation with the user if they only asked to push. If existing PRs are up to date, `submit` can leave them unchanged and append only the new child's PR to the existing remote stack. `gh stack push --remote REMOTE` only pushes branches; it does NOT create PRs or guarantee a UI-visible stack.
4. If PRs already exist but the GitHub UI does not show a stack, check them with `gh pr view NUMBER --repo OWNER/REPO --json state,baseRefName,headRefName,url`. Local `gh stack view` is not proof of remote linkage. Link existing open PRs bottom to top with `gh stack link BOTTOM_PR NEXT_PR [MORE_PRS] --remote REMOTE`. Prefer PR numbers to avoid branch pushes. Verify the command reports a created/updated stack and report its number.
5. If a PR was closed because its head branch was deleted, verify PR state, `git ls-remote --heads REMOTE BRANCH`, and `git rev-parse BRANCH`. With authorization, restore the branch using `git push REMOTE BRANCH:BRANCH`, then `gh pr reopen NUMBER --repo OWNER/REPO`; retry the requested stack operation. Check whether the PR can be reopened before recreating it.
6. When a parent branch gets a new commit, descendants may need cascading rebases and their PR bases must follow. Check `gh stack view --json` for `needsRebase`; run `gh stack rebase --help`, then ask before running `gh stack rebase` (which rebases the stack from parent to child). Resolve conflicts, stage only the resolved files, and continue with `gh stack rebase --continue`. Then ask before `gh stack submit --auto --remote REMOTE` to publish/sync the rewritten descendants and PR bases. Verify each PR head/base with `gh pr view NUMBER --repo OWNER/REPO --json headRefOid,baseRefName,headRefName,url` and confirm `gh stack view --json` shows no `needsRebase`.
7. If a direct `git push` succeeds but GitHub's PR head appears stale, verify the remote branch SHA with `git ls-remote --heads REMOTE BRANCH` and the PR via `gh pr view`. A successful push does not mean PR metadata updated. For stack branches, use the approved `gh stack submit --auto --remote REMOTE` sync path, then recheck PR heads and bases. If the parent commit changed, follow the cascading rebase procedure above.
8. If `gh stack push` reports `stale info`, compare local and remote commits with `git rev-parse BRANCH` and `git ls-remote --heads REMOTE BRANCH`. Distinguish an absent branch from an already-matching branch. Do not force-push an already-matching branch. `gh stack sync` and `gh stack rebase` can rewrite history: use only when needed, in a clean worktree.

Finish by checking PR bases/states and remote stack linkage, not only local tracking. Report the branch/PR order and any remaining mismatch.

## PR descriptions

Use the `draft-pr` skill for the title and body. For stack PRs, also keep each description scoped to its own diff rather than the whole stack, and note when integration belongs to a later PR.
