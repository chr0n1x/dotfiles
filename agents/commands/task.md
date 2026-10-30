---
name: task
description: Spawn a subagent in an isolated git worktree with a dedicated tmux window. The subagent works in the worktree, and every bash command is mirrored into the tmux pane so the user can watch. Use when the user asks to run a task in the background, in parallel, or in a separate worktree with a visible tmux pane.
user-invocable: true
argument-hint: "[task description, e.g. \"add dark mode to the settings page\"]"
allowed-tools: Bash(git:*), Bash(tmux:*), Bash(mkdir:*), Read, Write, Edit
---

# Task

Spawn a subagent in an isolated git worktree. The subagent works in the
worktree, and every bash command is mirrored into a tmux pane so the user
can watch.

This command composes the `worktree` and `tmux-ctrl` skills. Load them
before their corresponding steps. This command coordinates them; it does
not replace their rules.

## 0. Dispatch

If running inside maki, check whether the `maki-task` plugin is loaded by
looking for a `/task` command registered by that plugin (the command
palette or `maki.api` listing). If it is available, delegate to the
plugin's `/task` command and stop here - do not run the steps below.

If running in any other harness (Claude Code, pi, etc.), or if the maki
plugin is not available, proceed with the steps below using the harness's
native subagent mechanism (e.g. Claude's `Task` tool, pi's subagent).

## 1. Resolve the task

- Get a task description from the argument. If no argument is given, ask
  the user what the task is.
- Derive a short slug from the description (e.g. `add-dark-mode`,
  `fix-login-bug`). The slug is used for the branch name, worktree path,
  and tmux window name.
- Verify you can reach a tmux server: `tmux list-sessions`. If this
  fails, stop and tell the user that tmux is not reachable.

## 2. Create the worktree

Follow the `worktree` skill's workflow (step 3):

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO=$(basename "$REPO_ROOT")
WT_DIR="$HOME/.worktrees/$REPO/$SLUG"
BRANCH="worktree/$SLUG"

mkdir -p "$(dirname "$WT_DIR")"
git -C "$REPO_ROOT" worktree add "$WT_DIR" -b "$BRANCH"
```

If the branch already exists, ask whether to reuse it or pick a new slug.

## 3. Open the tmux window

Follow the `tmux-ctrl` skill's window-creation pattern (option 3):

```bash
SESSION=$(tmux display-message -p '#{session_name}')
tmux new-window -d -t "$SESSION" -n "wt-$REPO-$SLUG" -c "$WT_DIR"
WT_PANE=$(tmux list-panes -t "$SESSION:wt-$REPO-$SLUG" -F '#{pane_id}')
```

The window is named `wt-<repo>-<slug>` and starts in the worktree
directory. Capture the pane ID; the subagent prompt needs it.

## 4. Spawn the subagent

Use the harness's native subagent mechanism (e.g. Claude's `Task` tool,
pi's subagent). The subagent inherits the main agent's environment, so
the prompt must tell it explicitly to work in the worktree and use the
tmux pane as its shell.

**Base prompt (always):**

```
You are working in a git worktree at $WT_DIR on branch $BRANCH.
The main repo is at $REPO_ROOT - do NOT touch it.
Task: <task description>

Your shell is the tmux pane $WT_PANE in the worktree directory.
The user is watching it. Every command you run goes into that
pane and the user sees it live. You do NOT have a separate
shell.

Rules:
- Use tmux send-keys to run commands in the pane:
  1. tmux send-keys -t "$WT_PANE" -l '<command>'
  2. tmux send-keys -t "$WT_PANE" Enter
  3. Read the output: tmux capture-pane -t "$WT_PANE" -p -S -50
  4. For verbose output, increase -S -50 to -S -200 or more.
- All git commands use -C "$WT_DIR" (or cd there first).
- Do NOT push. Do NOT merge. Do NOT modify the main repo.
- When finished, summarize what you changed and the commit hash(es).
- You may split the pane to run concurrent commands or open new
  panes for long-running processes. The window is your sandbox.
  Do NOT touch panes or windows outside this one. Do NOT open
  popups.

Skills:
Before performing any specialized operation (committing, pushing,
opening a PR, code review, BDD workflow, etc.), check whether a
matching skill is available and load it. Skills encode repo-specific
conventions, confirmation gates, and step-by-step procedures that
override the defaults. If no matching skill exists, proceed with
your best judgment.
```

## 5. When the task is done

The subagent returns a summary. Relay it to the user, including the
commit hash(es) and the worktree path.

Ask the user, in order:
- "Merge `worktree/$SLUG` back to the main branch? (yes / no)"
  - Yes: `git -C "$REPO_ROOT" merge --no-ff "$BRANCH"`
- "Remove the worktree? (yes / no)"
  - Yes: `git -C "$REPO_ROOT" worktree remove "$WT_DIR"`
- "Close the tmux window `wt-$REPO-$SLUG`? (yes / no)"
  - Yes: `tmux kill-window -t "$SESSION:wt-$REPO-$SLUG"`
  (follow the tmux-ctrl kill confirmation rule)

## Rules

- **Never push from a worktree branch without explicit user
  confirmation.** The worktree is a local isolation boundary.
- **Never merge without asking.** Ask even if the worktree branch is
  clean and the main branch has no new commits.
- **Worktree path: `~/.worktrees/<repo>/<slug>`.** Do not create
  worktrees inside the repo directory.
- **Branch naming: `worktree/<slug>`.** The prefix keeps worktree
  branches distinguishable from regular feature branches.
- **Tmux window name: `wt-<repo>-<slug>`.**
- **One task per worktree.** For parallel tasks, create multiple
  worktrees. Each gets its own slug, branch, window, and subagent.
- **The subagent works in the worktree via git -C, not by changing
  the agent's cwd.** The main agent's working directory stays on the
  main repo.
- **Confirm the tmux pane target before the first write** per the
  tmux-ctrl skill's confirmation rule.

## Cleanup

If a worktree is left behind (session ended, agent crashed), clean it
up:

```bash
git worktree list

# Check for uncommitted changes before removing
git -C ~/.worktrees/<repo>/<slug> status --short

# Remove (refuses if dirty; stash or discard first)
git worktree remove ~/.worktrees/<repo>/<slug>

# Prune stale references
git worktree prune

# Kill the tmux window if one was opened
tmux kill-window -t "$(tmux display-message -p '#{session_name}'):wt-<repo>-<slug>" 2>/dev/null
```
