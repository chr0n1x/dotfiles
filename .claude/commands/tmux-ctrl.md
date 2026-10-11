---
name: tmux-ctrl
user-invocable: true
description: Inspect and drive the user's running tmux session - list sessions/windows/panes, capture pane output, send keystrokes, and create or kill panes. Use this skill when you need to see what is running in other panes, run a command in the user's tmux environment, or manage the session layout. Triggers when the user asks about their tmux session, other panes, or running processes they have on screen.
argument-hint: [target or tmux action, e.g. "main:2.1" or "run a command in a pane"]
allowed-tools: Bash(tmux*)
---

# tmux Control

When an agent runs inside a tmux pane, the `$TMUX` environment variable
points at the server socket and any `tmux` command reaches the running
server.

## Prerequisites

Before doing anything, verify you can reach a tmux server:

```bash
tmux list-sessions
```

If this fails or returns nothing, you are not attached to a reachable tmux
server and none of this works. (`$TMUX` being non-empty only means you are in
a pane of some server; `list-sessions` failing is the real signal.)

**Safety first:** `send-keys` without `-t` targets the *active pane of the
current session*, which is the pane you are running in. Do not send keys to
your own pane unless the user explicitly asked for it. Always use an explicit
`-t` target for anything that writes.

**Always confirm with the user before writing to a tmux pane for the first
time in a session.** The first `send-keys`, `new-window`, `split-window`, or
`kill-*` you issue should be preceded by a plain-language description of
exactly what will happen and to which target, then a yes/no question. Wait
for "yes" before proceeding. Subsequent writes in the same session do not
need re-confirmation unless the target changes in a way the user did not
anticipate (e.g. a new pane, a different window).

**Use a yes/no multiple-choice question for every confirmation in this
skill.** Always present a plain "yes" / "no" choice (not free-form text) so
the user can answer with a tap, not a sentence. Phrase the question around
what you are about to do, e.g. "Split window 1 with a vertical pane and run
the test there? [yes / no]".

**Prefer running commands in a pane the user can see.** If the current
window has only one pane - the agent's own nvim/harness instance - do not run
the command there. Ask the user first (yes/no) if a vertical split
(`split-window -h`) is ok, and if yes, create it, run the command there, and
kill the pane when done (after asking). If the window already has other
panes, use one of those rather than the agent's own pane.

**Split direction pattern:** the first split is always vertical (`-h`). Any
further splits relative to the pane you just created alternate: horizontal
(`-v`) next, then vertical, and so on. Target the newly created pane
(`-t <pane_id>`), not the window, so the direction is relative to that pane
specifically.

**Always ask before `kill-pane` or `kill-window`, even if you created the
pane yourself and the task is done.** A pane is a visible part of the user's
screen; killing one changes what they see. State which target and why, then
ask yes/no, then kill.

## Targets

A full target is `session:window.pane` (e.g. `main:2.1`). Partial targets
(`main`, `main:2`, `main:2.1`) all resolve. Use `-a` / all-panes flags where
possible so you do not need to know the current session name.

## Reading

```bash
# List everything with stable identifiers
tmux list-sessions -F "#{session_name}"
tmux list-windows -t <session> -F "#{window_index} #{window_name}"
tmux list-panes -t <session>:<win> -F "#{pane_index} #{pane_current_path} #{pane_current_command}"

# Capture the visible screen of a pane
tmux capture-pane -t <target> -p

# Capture the whole scrollback
tmux capture-pane -t <target> -p -S -

# What is the pane actually running (useful to pick a target)
tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index} #{pane_current_command}"
```

Use `capture-pane -p` (not `-pS`) for a one-shot screen grab. When you need
recent history (build output, test logs), cap it - `tail -50` keeps the
context manageable:

```bash
tmux capture-pane -t <target> -p -S -50 | tail -50
```

Only use `-S -` (whole scrollback) when the user explicitly asks for it, and
even then pipe through `tail` or `grep` before printing it all.

## Writing

Send keystrokes to a specific pane:

```bash
tmux send-keys -t <target> -l 'git status'
tmux send-keys -t <target> Enter
```

`send-keys` splits arguments at spaces into individual key names, **not**
words. A bare `"ls -la"` works only because `ls`, `-`, and `la` all happen
to be valid key names; anything else - `git`, `node`, `cargo`, a path with a
slash - is misparsed into key-name tokens silently, not with an error. For
any real command or arbitrary text, always use `-l` (literal).

Run a command in a new window or pane instead of typing it into an
existing one. Ask the user first which of these they want:

1. **Use an existing pane** - send keys to a specific pane already in the
window.
2. **Split the focused pane** - `split-window` in the current window.
3. **Open a new window** - `new-window` in the current session; the agent
can use it freely without touching the user's existing layout.

```bash
# Option 1: existing pane
tmux send-keys -t <target> -l 'make build'
tmux send-keys -t <target> Enter

# Option 2: split the focused pane, capture the new pane_id
NEW_PANE=$(tmux split-window -h -t <session>:<win> -P -F '#{pane_id}')
tmux send-keys -t "$NEW_PANE" -l 'cargo test'
tmux send-keys -t "$NEW_PANE" Enter

# Option 3: new window in the current session, then target it like option 1
tmux new-window -d -t <session> -n build
tmux send-keys -t <session>:build -l 'make build'
tmux send-keys -t <session>:build Enter
```

Always use `-P -F '#{pane_id}'` with `split-window` to capture the new
pane's stable id. Never guess the new pane index; after any kill or
renumber, index-based targets will point at the wrong pane.

## Managing layout

```bash
tmux list-panes -t <target> -F "#{pane_id}"     # pane_ids are stable across renumbering
tmux kill-pane -t <pane_id>
tmux kill-window -t <session>:<win>
tmux rename-window -t <session>:<win> <name>
tmux select-pane -t <target>                      # changes the active pane; restore with the previous pane_id
tmux resize-pane -t <target> -x 200
```

Prefer `#{pane_id}` over `window.pane` indices for `kill-pane` and
`select-pane`, since splitting renumbers indices.

## Combining with other skills

The Neovim terminal the agent runs in is itself a tmux pane. If you need to
see what Neovim is showing, either `capture-pane` the pane that hosts it, or
use the `nvim-ctrl` skill to query buffers directly.

`watch-tests` is the main consumer of this skill's Reading primitives: it
polls every pane on a loop, parses the output with per-runner grep patterns,
and fixes failures until green. When a task is "watch the tests and fix what
fails", load `watch-tests` - it owns the loop and the runner patterns; this
skill owns only the `tmux` calls underneath it.
