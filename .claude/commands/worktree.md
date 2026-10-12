---
name: worktree
description: Create an isolated git worktree for a task, optionally open a tmux window in it, and optionally spawn a subagent to work in it. Use when the user asks to work on a task in isolation, in parallel, or in a worktree.
user-invocable: true
argument-hint: "[task name, e.g. \"add-dark-mode\" or \"fix-login-bug\"]"
allowed-tools: Bash(git:*), Bash(tmux:*), Bash(mkdir:*), Bash(rm:*), Read, Write, Edit
---

# Worktree

Isolate a task in its own git worktree so the main branch and the agent's main pane are untouched.

## Workflow

1. **Identify the task.** Get a short slug from the user or the argument (e.g. `add-dark-mode`, `fix-login-bug`). This slug is used for the branch name, worktree path, and tmux window name.

2. **Ask the user what to set up.** Use the gate/question tool with two independent yes/no questions:
   - "Open a tmux window in the worktree so you can watch it? (yes / no)"
   - "Spawn a subagent to do the work in the worktree? (yes / no)"
     - If no to both: the agent creates the worktree and the user works in it directly (e.g. opens a new terminal, cds into it).
     - If yes to subagent: the main agent stays on the main branch and reports the subagent's progress. The user can also watch the tmux window if they opened one.

3. **Create the worktree.**

   ```bash
   REPO_ROOT=$(git rev-parse --show-toplevel)
   REPO=$(basename "$REPO_ROOT")
   WT_DIR="$HOME/.worktrees/$REPO/$SLUG"
   BRANCH="worktree/$SLUG"

   mkdir -p "$(dirname "$WT_DIR")"
   git -C "$REPO_ROOT" worktree add "$WT_DIR" -b "$BRANCH"
   ```

   If the branch already exists, ask whether to reuse it or pick a new slug.

4. **Open a tmux window (if requested).**

   Use the `tmux-ctrl` skill's window-creation pattern (option 3):

   ```bash
   SESSION=$(tmux display-message -p '#{session_name}')
   tmux new-window -d -t "$SESSION" -n "wt-$SLUG" -c "$WT_DIR"
   ```

   The window is named `wt-<slug>` and starts in the worktree directory. The user can switch to it with `C-b <window-number>`.

5. **Spawn a subagent (if requested).**

   Use the `task` tool. The subagent inherits the main agent's environment, so the prompt must tell it explicitly to work in the worktree:

   ```
   task(subagent_type="general", prompt="""
   You are working in a git worktree at $WT_DIR on branch $BRANCH.
   The main repo is at $REPO_ROOT - do NOT touch it.

   Task: <task description>

   Rules:
   - All git commands use -C "$WT_DIR" (or cd there first).
   - Commit your work on the worktree branch when done.
   - Do NOT push. Do NOT merge. Do NOT modify the main repo.
   - When finished, summarize what you changed and the commit hash(es).
   """)
   ```

   The main agent reports the subagent's result to the user. If the user opened a tmux window, the subagent's terminal output is not visible in that window (the subagent runs in the agent's own pane). The tmux window is for the user to inspect the worktree state, run tests, or edit files directly.

6. **When the task is done.**

   Ask the user, in order:
   - "Merge `worktree/$SLUG` back to the main branch? (yes / no)"
     - Yes: `git -C "$REPO_ROOT" merge --no-ff "$BRANCH"`
   - "Remove the worktree? (yes / no)"
     - Yes: `git -C "$REPO_ROOT" worktree remove "$WT_DIR"`
   - If a tmux window was opened: "Close the tmux window `wt-$SLUG`? (yes / no)"
     - Yes: `tmux kill-window -t "$SESSION:wt-$SLUG"` (ask again per the tmux-ctrl kill confirmation rule)

## Rules

- **Never push from a worktree branch without explicit user confirmation.** The worktree is a local isolation boundary.
- **Never merge without asking.** Ask even if the worktree branch is clean and the main branch has no new commits.
- **Worktree path: `~/.worktrees/<repo>/<slug>`.** Do not create worktrees inside the repo directory.
- **Branch naming: `worktree/<slug>`.** The prefix keeps worktree branches distinguishable from regular feature branches.
- **Tmux window name: `wt-<slug>`.**
- **One worktree per task.** For parallel tasks, create multiple worktrees. Each gets its own slug, branch, window, and (optionally) subagent.
- **The subagent works in the worktree via git -C, not by changing the agent's cwd.** The main agent's working directory stays on the main repo.

## Cleanup

If a worktree is left behind (session ended, agent crashed), clean it up:

```bash
git worktree list

# Check for uncommitted changes before removing
git -C ~/.worktrees/<repo>/<slug> status --short

# Remove (refuses if dirty; stash or discard first)
git worktree remove ~/.worktrees/<repo>/<slug>

# Prune stale references
git worktree prune
```
