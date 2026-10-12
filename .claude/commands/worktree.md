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

2. **Ask the user what to set up.** Use a yes/no confirmation (in maki, the `gate` tool; in other harnesses, whatever confirmation mechanism is available) with one question:
   - "Spawn a subagent to work in the worktree?"
     - If yes: open a tmux window in the worktree automatically (so the user can watch), then spawn the subagent.
     - If no: just create the worktree. The user works in it directly (e.g. opens a new terminal, cds into it). No tmux window needed.

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

4. **Open a tmux window (only if subagent was requested).**

   Use the `tmux-ctrl` skill's window-creation pattern (option 3):

   ```bash
   SESSION=$(tmux display-message -p '#{session_name}')
   tmux new-window -d -t "$SESSION" -n "wt-$REPO-$SLUG" -c "$WT_DIR"
   ```

   The window is named `wt-<repo>-<slug>` and starts in the worktree directory. The user can switch to it with `C-b <window-number>`.

5. **Spawn a subagent (only if requested).**

   Use the `task` tool. The subagent inherits the main agent's environment, so the prompt must tell it explicitly to work in the worktree.

   **Base prompt (always):**

   ```
   You are working in a git worktree at $WT_DIR on branch $BRANCH.
   The main repo is at $REPO_ROOT - do NOT touch it.
   Task: <task description>

   Rules:
   - All git commands use -C "$WT_DIR" (or cd there first).
   - Commit your work on the worktree branch when done.
   - Do NOT push. Do NOT merge. Do NOT modify the main repo.
   - When finished, summarize what you changed and the commit hash(es).
   ```

   **Always** (the tmux window is opened in step 4): capture its pane ID, then add this to the prompt:

   ```bash
   WT_PANE=$(tmux list-panes -t "$SESSION:wt-$REPO-$SLUG" -F '#{pane_id}')
   ```

   ```
   TMUX WINDOW (required): You have a dedicated tmux window
   (wt-$REPO-$SLUG, pane $WT_PANE) in the worktree directory. The
   user is watching this window. This window is yours to use.

   Mirror every bash command you run into the main pane so the user
   sees it:
   1. Run it in your own shell (to get the result).
   2. Mirror it: tmux send-keys -t "$WT_PANE" -l '<command>'
   3. Then:    tmux send-keys -t "$WT_PANE" Enter

   You may also use the tmux-ctrl skill to manage the window's layout:
   - Split the pane to run concurrent commands (e.g. a server in one
     half, tests in the other).
   - Open new panes for long-running processes (servers, watchers).
   - Use display-popup for quick output checks.
   - The window is your sandbox. The user watches whatever you put
     in it. Do NOT touch panes or windows outside this one.

   Do NOT mirror file edits (read/edit/grep) - only bash commands.
   ```

6. **When the task is done.**

   Ask the user, in order:
   - "Merge `worktree/$SLUG` back to the main branch? (yes / no)"
     - Yes: `git -C "$REPO_ROOT" merge --no-ff "$BRANCH"`
   - "Remove the worktree? (yes / no)"
     - Yes: `git -C "$REPO_ROOT" worktree remove "$WT_DIR"`
   - If a tmux window was opened: "Close the tmux window `wt-$REPO-$SLUG`? (yes / no)"
     - Yes: `tmux kill-window -t "$SESSION:wt-$REPO-$SLUG"` (ask again per the tmux-ctrl kill confirmation rule)

## Rules

- **Never push from a worktree branch without explicit user confirmation.** The worktree is a local isolation boundary.
- **Never merge without asking.** Ask even if the worktree branch is clean and the main branch has no new commits.
- **Worktree path: `~/.worktrees/<repo>/<slug>`.** Do not create worktrees inside the repo directory.
- **Branch naming: `worktree/<slug>`.** The prefix keeps worktree branches distinguishable from regular feature branches.
- **Tmux window name: `wt-<repo>-<slug>`.**
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
