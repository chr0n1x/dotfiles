---
name: nvim-orchestrate
user-invocable: true
description: Delegate and orchestrate work across coding agents running in the user's Neovim. Use when the user asks to delegate or orchestrate work across agents in their nvim, to coordinate parallel agent work, or to "use the other agents".
---

# Neovim Agent Orchestration

Coordinate existing agent terminals in one Neovim. Keep the user's editor and
agents alive, isolate writes in worktrees, verify every result, and integrate one
branch at a time.

Load `nvim-ctrl` before querying or writing to Neovim. Load `worktree` for
isolation, `commit-push` for commit message rules, `rebase` before integration,
and `watch-tests` for test runs. Use `tmux-ctrl` only if the task involves tmux.
Prefer the harness's native parallel/task mechanism where it fits.

Scratch files (briefs, done files, helper scripts) go in
`${XDG_STATE_HOME:-$HOME/.local/state}/nvim-orchestrate/<task>/` unless the user
names another place.

## 1. Establish constraints

Ask only for what cannot be discovered:

- Which agents should be used, if unclear.
- A total spend cap, whether it includes prior spend, and each pre-existing
  session's starting cost.
- Model, file ownership, sequencing, or permission constraints.
- The repo's test command, and whether concurrent runs interfere.
- Approval before committing uncommitted work to serve as the shared base.

Do not assign work until the cap and baselines are known. Record costs no
footer exposes (including your own) as unknown.

## 2. Discover the agents

Verify `$NVIM`, then list terminal buffers (`buftype=terminal`) through
`nvim-ctrl`. Ask the user how agent terminals are named or looked up if it is
not obvious (buffer name, `b:term_title`, or a helper in their config). Call
that lookup `bufnr(name)` below.

For each candidate, without changing focus or contents:

1. Read its last screenful and parse the footer for model, permission mode, and
   cost. If the footer format is unclear, ask.
2. Treat clearly autonomous modes (e.g. `yolo`, `auto`) as autonomous; treat
   anything else or uncertain as prompting.
3. Walk your own process ancestry (`ps -o ppid= -p "$pid"` until PID 1) and
   compare against each terminal's `jobpid`. The match is you; never send to it.
   If unsure which terminal is you, ask.

Keep an inventory (name, buffer, PID, model, mode, starting cost, current cost,
status) and refresh it before every assignment.

## 3. Plan assignments

Split work into independently verifiable scopes with explicit file ownership.
Strongest model gets the riskiest or most cross-cutting work; cheaper models get
mechanical edits, focused tests, or narrow investigations; prompting agents get
read-only reviews. No two agents own the same writable file. Only the
orchestrator edits shared instruction files (e.g. `AGENTS.md`); agents propose
such changes in their done files. The orchestrator owns integration, commit
rewording, and the final full test run. Reuse idle agents; never start a
replacement while a usable terminal exists.

## 4. Prepare isolation

One branch and worktree per writing agent, all from the same committed base.
Follow `worktree`, but integrate via rebase, not merge commits.

1. Inspect the source checkout for pre-existing changes; ask before committing
   them into the base.
2. Add the worktree parent to `.git/info/exclude`, not `.gitignore`.
3. Create each branch/worktree from the exact base SHA. Symlink shared caches if
   worktrees need the same prepared dependencies.
4. Never place an agent in the main checkout or another agent's worktree.

If concurrent test runs interfere, give every agent a serialized wrapper and
forbid calling the test command directly:

```sh
#!/bin/sh
LOCK="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/<repo>-test.lock"
until mkdir "$LOCK" 2>/dev/null; do
  holder=$(cat "$LOCK/pid" 2>/dev/null)
  [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null && rm -rf "$LOCK"
  sleep 5
done
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT INT TERM
<test command> "$@"
```

## 5. Write briefs

One shared rules file plus one task file per agent; never paste long briefs into
a terminal.

Shared rules: base SHA, worktree path, branch, main checkout to avoid; the test
wrapper and cadence; global file ownership; no push, merge, rebase, force, edits
outside the worktree, untracked-file cleanup, or touching others' files; follow
`commit-push` message format with the exact `AI Model:` value for that agent;
done-file path, written last.

Task file: goal and acceptance criteria; owned and forbidden files; required
tests; commit expectations; done-file contents (commit SHAs and full messages,
changed files, skipped work with reasons, test commands and results, concerns,
proposed instruction changes).

## 6. Send the work

Write the one-line prompt to a file, send its text with `chansend`, then send
`\r` about 400 ms later:

```sh
#!/bin/sh
# Usage: send_agent.sh <name> <message-file>
nvim --server "$NVIM" --remote-expr "luaeval('(function(n, p) local m=table.concat(vim.fn.readfile(p), \" \"); local b=<bufnr lookup>(n); local j=vim.b[b].terminal_job_id; vim.fn.chansend(j, m); vim.defer_fn(function() vim.fn.chansend(j, \"\\r\") end, 400); return n end)(_A[1], _A[2])', ['$1', '$2'])"
```

Prompt shape:

```text
Read /abs/shared.md and /abs/task-agent.md, follow them exactly, and write /abs/agent-done.md last.
```

Re-check the target against the inventory right before sending.

## 7. Watch progress and spend

Run a background monitor (loop every ~60s) that prints one line when a done file
appears, when tracked spend crosses each $5 boundary, and every ~15 minutes. Read
costs by grepping the last few footer lines of each agent buffer for `$<number>`
and subtracting that agent's baseline. If a footer shows several figures (e.g.
session vs cumulative), pick the one matching the baseline and say which. A
running script does not see later edits; restart it to change agents or
baselines.

Report unknown costs alongside the tracked total. Near the cap, stop handing out
work; let assigned agents finish unless told otherwise.

## 8. Verify every report

A done file is a signal, not proof. For each agent: read the done file; list
branch commits from the base and check each full message against `commit-push`;
read the full diff; compare paths with owned/forbidden files; check for
uncommitted or untracked work; inspect tests and implementation; re-run tests
through the wrapper if results are missing, stale, or ambiguous. Reject or send
scoped follow-up on any failure.

## 9. Integrate sequentially

Follow `rebase` and `commit-push`. For each verified branch:

1. Rebase onto the current default branch; no merge commits. Resolve conflicts
   preserving both the branch's accepted behavior and already-landed work.
2. Reword commits that break the message format, e.g.
   `git rebase <default> -x 'git commit --amend -q -m "$(git log -1 --format=%B | sed "s|^AI Model: .*|AI Model: <value>|")"'`.
   Fold review fixes in with `git commit --fixup=<sha>` and
   `GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash <default>`.
3. Run the full suite on the rebased branch through the wrapper.
4. Only on pass, `git merge --ff-only <branch>`. On failure, stop and fix or
   reject before the next branch.
5. Remove the worktree only after the user confirms cleanup.

Do not push unless the user asks and the `commit-push` gate allows it.

## Safety

- Never kill, restart, close, or replace the user's tmux, Neovim, or any agent
  terminal.
- Never send to yourself or to a terminal whose identity is uncertain.
- Never bypass a permission prompt or widen an agent's permissions.
- Never merge, rebase, push, commit a shared base, or remove work without user
  confirmation.
- One orchestrator owns ownership, spend, verification, and integration
  throughout.
