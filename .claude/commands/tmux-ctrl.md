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
time in a session.** The first `send-keys`, `new-window`, `split-window`,
`display-popup`, or `kill-*` you issue should be preceded by a
plain-language description of exactly what will happen and to which target,
then a yes/no question. Wait for "yes" before proceeding. Subsequent writes
in the same session do not need re-confirmation unless the target changes in
a way the user did not anticipate (e.g. a new pane, a different window, a
new popup).

**Use a yes/no multiple-choice question for every confirmation in this
skill.** Always present a plain "yes" / "no" choice (not free-form text) so
the user can answer with a tap, not a sentence. Phrase the question around
what you are about to do, e.g. "Split window 1 with a vertical pane and run
the test there? [yes / no]".

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
existing one. Ask the user first which of these they want (use the gate
or question tool for a selectable list, not free-form text):

1. **Use an existing pane** - send keys to a specific pane already in the
window.
2. **Split the focused pane** - `split-window` in the current window.
   Use this for two concurrent commands (one per half).
3. **Open a new window** - `new-window` in the current session; the agent
can use it freely without touching the user's existing layout.
4. **Floating popup** - `display-popup`; a floating terminal positioned
proportionally over the current view. Good for showing one long-running
command's output without rearranging panes. Only one popup per client;
for two concurrent commands use a split (option 2) so both are visible
side by side.

Follow-up question (via gate/question tool, for options 1-3):
- **"Close it when the command finishes?"**
  - Yes: kill the pane/window after the command exits (ask again right
    before killing, per the kill confirmation rule).
  - No: leave it for the user.

Popups (option 4) always stay open and end with
`read -p "[press esc to close]"`. The user closes with Escape.
The popup blocks the client, so the agent has no control over its
lifecycle (tmux 3.5a). No follow-up question needed.

Do not block-wait for the command to finish. Check the log file for the
exit code line when you need the result; if it is not there yet, the
command is still running. If you must wait between checks, keep `sleep`
under 10 seconds - never longer.

```bash
# Option 1: existing pane
tmux send-keys -t <target> -l 'make build'
tmux send-keys -t <target> Enter

# Option 2: split the focused pane, capture the new pane_id
# Resize to 20% of window width to keep the main pane at full working size.
# Select the original pane back so the user keeps focus on nvim.
# Use the same tee-to-log pattern so the agent can detect completion.
# "Close it?" = yes: agent polls the log for the exit code line, then
# kill-pane (asking first, per the kill confirmation rule).
ORIG_PANE=$(tmux display-message -p '#{pane_id}')
NEW_PANE=$(tmux split-window -h -t <session>:<win> -P -F '#{pane_id}')
W=$(tmux display-message -p '#{window_width}')
tmux resize-pane -t "$NEW_PANE" -x $((W * 20 / 100))
# Let tmux settle the new layout before grabbing focus back,
# or the layout engine and select-pane fight over the active pane.
sleep 1
tmux select-pane -t "$ORIG_PANE"
LOG="<cwd>/.agents/<nvim-pid>-<agent-pid>-<task-name>.log"
mkdir -p "$(dirname "$LOG")"
tmux send-keys -t "$NEW_PANE" -l "bash -c 'cargo test 2>&1 | tee $LOG; ec=\${PIPESTATUS[0]}; echo \"exit: \$ec\" >> $LOG'"
tmux send-keys -t "$NEW_PANE" Enter
# Later, once "exit:" appears in the log:
# tmux kill-pane -t "$NEW_PANE"   (ask the user first)
# Focus is already on the original pane; no need to re-select.

# Option 3: new window in the current session, then target it like option 1
tmux new-window -d -t <session> -n <task-name>
tmux send-keys -t <session>:<task-name> -l 'make build'
tmux send-keys -t <session>:<task-name> Enter

# Option 4: floating popup for a finite command
#   -T <title>  the popup's title bar text
#   -w/-h       width/height (default: 50% of terminal)
#   -d <dir>    start directory
# All output goes through tee to a deterministic log file in
# <cwd>/.agents/ - the agent reads the log since it has no capture-pane
# access to a popup. The exit code is appended to the log. The popup
# stays open after the command; the user closes with Escape.
# Log path: <cwd>/.agents/<nvim-pid>-<agent-pid>-<task-name>.log
#   nvim-pid:  from the $NVIM socket path (e.g. /run/user/1000/nvim.2208455.0)
#   agent-pid: $$ (the shell running the command)
CWD="$(tmux display-message -p '#{pane_current_path}')"
NVIM_PID=$(echo "$NVIM" | grep -oP '\d+(?=\.)')
AGENT_PID="$$"
LOG="$CWD/.agents/${NVIM_PID}-${AGENT_PID}-<task-name>.log"
mkdir -p "$CWD/.agents"
# Position and size are proportional to the window so they scale:
#   x = 48% of width (slightly right of centre)
#   y = 40% of height
#   w = 28% of width
#   h = 31% of height
W=$(tmux display-message -p '#{window_width}')
H=$(tmux display-message -p '#{window_height}')
PX=$((W * 48 / 100))
PY=$((H * 40 / 100))
PW=$((W * 28 / 100))
PH=$((H * 31 / 100))
tmux display-popup \
  -t "$(tmux display-message -p '#{pane_id}')" \
  -T "<task-name>" \
  -w "$PW" -h "$PH" \
  -x "$PX" -y "$PY" \
  -d "$CWD" \
  "bash -c '<command> 2>&1 | tee $LOG; ec=\${PIPESTATUS[0]}; echo; echo \"exit: \$ec\" | tee -a $LOG; read -p \"[press esc to close]\"'"
# The agent reads the result from the log path:
#   tail "$LOG"  (check the exit code line, grep for failures)
```

Always use `-P -F '#{pane_id}'` with `split-window` to capture the new
pane's stable id. Never guess the new pane index; after any kill or
renumber, index-based targets will point at the wrong pane.

A popup is a client-level overlay, independent of pane indices and
window layout. The agent interacts with it only through the log file.
For commands where the agent needs `send-keys` or `capture-pane`, use
options 1-3.

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

The Neovim terminal the agent runs in is itself a tmux pane. Use the
`nvim-ctrl` skill to query buffers directly instead of `capture-pane`.
`watch-tests` builds on this skill's Reading primitives for its poll loop.
