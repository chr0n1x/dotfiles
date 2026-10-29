---
name: noodle-reset
description: Reset a project's Noodle run state while preserving its setup.
  Inventory and back up first, ask before each destructive action, and
  report runtime, worktree, branch, review and log cleanup separately.
user-invocable: true
argument-hint: "[target repo path, default: pwd]"
---

# Noodle Reset

Return an approved project's run state to the agreed starting point.
This is not reinstall or init. Never install, update, commit, start a
loop or discard anything without asking. Never use `noodle start --once`.
No ownership may be inferred from a directory or branch name alone.

Approval model: Step 1 ends with one proposed plan (exact PIDs, paths,
branches, what is kept). Once the user approves it, carry out its items
without asking again for each, and report what was done at each step. Ask
again, separately, only for: anything not in the plan, forcing removal of a
dirty or locked worktree, forcing deletion of an unmerged branch, deleting a
remote branch or closing a PR, `git worktree prune`, removing
credential-bearing backups, and stopping a process not in the plan. The
"ask" lines in the steps below mean: covered by the approved plan, or ask.

## Step 1: Resolve target and inventory

Resolve the argument or cwd to its Git root. Read project instructions,
`.noodle.toml`, available setup guide and brain index. Read no secret
contents. Inspect `noodle --help` and `noodle reset --help` before using
reset; if absent or its scope differs, stop and ask rather than inventing
a replacement. Do not run reset during discovery.

Inventory paths and identities, without printing raw cook prompts or
credential values:

- Loop PID and parent, active cook PIDs and their worktrees; owned local
  helper/watch processes and listeners. Match PIDs to this project.
- Bootstrap resources listed in the project's setup guide: whether each is
  running or in sync, using the verification note's read-only check. They are
  kept by default.
- Runtime files, sessions, events, pending reviews and draft-PR records.
  Use the snapshot or pending-review.json for review state, not only
  orders.json, which is a legacy mirror.
- `git worktree list --porcelain`, each worktree's tracked/untracked
  changes and relevant ignored outputs. Inspect leftover directories
  under `.worktrees/` separately; they may not be registered worktrees.
- For each candidate worktree, its branch and symlinks, their resolved
  targets, and whether targets are shared root setup, dependencies or
  credentials. Do not follow links when preparing cleanup.
- Local branches, their tips, delivery remote branches and draft PRs.
  Confirm delivery destinations from config; do not assume origin.
- Setup files, backlog/plans, exact run log/output paths, external
  generated credential locations and secret-bearing backup locations.
- Build and edit backups: `bin/noodle.bak-*` in the plugin directory
  (earlier binaries kept by rename-swaps) and adapter backups such as
  `/tmp/backlog-sync.bak`. List each with its date and size.

Show a proposed keep/remove list with exact paths, branch refs and
process IDs. Ask which resources belong to this reset. Unclear ownership
means keep and ask. Report the inventory before changing anything.

## Step 2: Agree on preservation and back up

Preserve by default: `.noodle.toml`, `.agents/skills/` and local patches,
`adapters/`, brain verification note and helper scripts, MCP config,
task-source notes, indexes, guides, backlog, plans and archives.
Credentials and outside-repo runbook output are not runtime state.

Ask for a private backup destination outside every cleanup target.
Warn if the backup includes credential-bearing MCP config or evidence.
Do not copy credential files unless separately approved. Never print
secret values. Ask before writing or overwriting backup files.

Agree which run evidence and branch tips to preserve before runtime
reset removes their records. Back up approved setup/backlog/evidence and
record the inventory outside `.noodle/`. Copy shared setup from its real
root, not by following every worktree link. Protect sensitive backups
with directory mode 700 and file mode 600 as applicable.

Verify required backups are readable and match their sources without
printing contents. If active cooks can still write, treat this as an
initial backup; refresh it after Step 3 before reset. If a required backup
fails, stop. Report backup location, contents by path and omitted secrets.

## Step 3: Stop only approved processes

Ask immediately before stopping the identified loop PID. If cooks are
active, show their work and ask whether to wait or interrupt; interruption
can lose verification and reset work on restart. Do not proceed while
unapproved writers remain.

On approval, send `kill -INT <specific loop PID>` and wait for exit.
Check the identified cooks have exited, and look for helpers they started
(test runners, local servers) that survived with parent pid 1 in a worktree.
Ask separately before terminating any survivor. Never use name-based process
killing.

For an owned local harness, ask before stopping each process. Stop the
identified npm/watch parent before a child it would restart, then check
the listener is gone. Do not stop shared Docker, Redis/Valkey or someone
else's service by default. Do not stop bootstrap processes (from the setup
guide) unless the user asks: the next session needs them, and the user
restarts them. Never reseed or wipe the shared account as part of reset.

Refresh approved backups after writers stop. Report stopped PIDs,
listeners checked, remaining processes and final backup status.

## Step 4: Reset runtime state only

Explain and ask immediately before `noodle reset` in the confirmed root.
It clears `.noodle/` runtime contents: orders, sessions, events, reviews,
draft-PR records and control files. It does not remove worktrees, local
or remote branches, actual draft PRs, backlog, or temporary logs.

Run only after approval, using the installed help's syntax. Verify and
report what changed and what remains. Stop on failure or unexpected scope;
do not replace reset with recursive directory deletion.

## Step 5: Remove approved worktrees safely

For each inventoried worktree, recheck ownership, changes and backup.
Ask before unlinking its explicitly listed symlinks. Unlink the links
themselves, never their targets, before removing the worktree. Confirm
shared root brain, skills, dependencies and credentials still exist.

Do the unlink with a loop that cannot silently skip: run it under `bash -c`
(zsh does not split an unquoted variable, so `for l in $LIST` runs once with
the whole string, matches nothing and prints "skipped"), test each path with
`[ -L ]` before `unlink`, and count the links removed against the inventory.
After the loop, `find <worktree> -maxdepth 2 -type l` must print nothing, and
every link target from the inventory must still exist, before any
`git worktree remove` runs. Treat any "not a link, skipped" line for a path that
the inventory lists as a stop.

Ask separately before `git worktree remove <exact path>`. If Git refuses
because it is dirty, locked or otherwise unsafe, report why and ask;
never silently add `--force`. A force removal needs its own approval
after the user sees what would be lost.

For a leftover directory not registered with Git, inventory contents and
ask before removing specific files or that specific directory. Do not
recursively delete `.worktrees/` or use wildcards.

Review stale registration candidates before offering `git worktree prune`.
Ask separately: prune can affect stale entries outside this reset.
Report each unlink/removal, preserved targets, refusals and registrations
left. Never remove another repo's worktree as a side effect.

## Step 6: Decide branches, PRs and logs separately

Runtime reset did not delete any branch or close any PR. Reconcile these
against the saved inventory, not now-empty runtime records.

Ask before each named local branch deletion, showing tip and merge status.
Prefer the normal safe delete; ask again before forcing an unmerged branch.
Ask independently before deleting each branch on its confirmed delivery
remote or closing each confirmed draft PR. Never use broad matching or
assume all noodle-prefixed branches are disposable.

For each approved log/output path, inspect ownership and ask before
removal. Ignored outputs do not appear in ordinary git status. Delete
only explicitly resolved paths, never wildcard `/tmp` or broad directories.
Leave unrelated logs, session scratchpads and other projects untouched.

Warn that external runbook backups can hold expired secrets. Ask for a
retention decision; do not sweep runbook backup directories, `.envrc`,
`.vault-token`, credentials, CA bundles or shared lock files by default.

For each binary backup (`bin/noodle.bak-*`) and adapter backup, ask keep or
remove. Keep at least the newest binary backup by default: it is the only
rollback if the installed binary misbehaves. Before removing an adapter
backup, confirm the live adapter passes `bash -n` and matches what the user
expects. Remove only the exact paths approved.

Report local/remote branches, PRs, backups and exact log paths changed or
retained.

## Step 7: Backlog and final state

Ask whether to preserve the backlog or restore the init seed. Keep it by
default. Before an approved reset, verify the saved backlog and evidence:

```markdown
# Todos

<!-- next-id: 1 -->

## Inbox
```

Ask separately before removing any ticket-specific plan, patch or review.
Never clear brain/plans or brain/archive wholesale. Keep the setup and
indexes; report where historical evidence was saved.

Compare the final inventory with the agreed post-init state. Check root
status, worktree registrations, retained setup files and unresolved
processes/reviews/branches. Confirm no shared symlink target was removed.
Report each action's observed result, skipped actions, backup location
and remaining resources, including open PRs or remote branches.

Report the bootstrap state with the note's read-only check: what is
running, and whether the user must restart a process or reseed before the
next loop session.

Do not run init or start a loop to test the reset. The next step, if the
user wants new work, is `/noodle-feed`.
