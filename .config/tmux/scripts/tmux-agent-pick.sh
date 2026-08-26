#!/usr/bin/env bash
# Agent picker for tmux - replacement for the stock tmux-agent-status fzf
# switcher (prefix S). The stock switcher passes --listen=<unix socket> to
# fzf, which newer fzf builds reject ("invalid listen port"), so this is a
# plain fzf popup with no socket: works on any fzf version.
#
# Reads the same status files the plugin maintains in ~/.cache/tmux-agent-status/
# and pipes rows into fzf. Selecting a row (enter) switches to that
# session/window. The switch is done inside the popup command itself by piping
# fzf's stdout into a small handler, since display-popup does not return the
# popup command's stdout to the calling shell.

set -uo pipefail

STATUS_DIR="$HOME/.cache/tmux-agent-status"
PARKED_DIR="$STATUS_DIR/parked"
WAIT_DIR="$STATUS_DIR/wait"
PANE_DIR="$STATUS_DIR/panes"

status_icon() {
    local c='\033[0m'
    case "$1" in
        working) printf '\033[32m\xe2\x97\x8f\033[0m' ;;  # green ●
        wait)    printf '\033[33m\xe2\x97\x8b\033[0m' ;;  # yellow ○
        ask)     printf '\033[31m?\033[0m' ;;              # red ?
        done)    printf '\033[34m\xe2\x96\xa1\033[0m' ;;  # blue ■
        parked)  printf '\033[35m\xe2\x97\x86\033[0m' ;;  # magenta ◆
        *)       printf '\xe2\x94\x80' ;;                  # light gray -
    esac
}

# Pane status for one pane id, mirroring the plugin's resolution order:
# parked > wait > per-pane status file > session status file.
pane_status() {
    local session="$1" pane_id="$2"
    [ -f "$PARKED_DIR/${session}_${pane_id}.parked" ] && { echo parked; return; }
    if [ -f "$WAIT_DIR/${session}_${pane_id}.wait" ]; then
        local expiry now
        expiry=$(cat "$WAIT_DIR/${session}_${pane_id}.wait" 2>/dev/null)
        now=$(date +%s)
        if [ -n "$expiry" ] && [ "$expiry" -gt "$now" ]; then echo wait; return; fi
    fi
    if [ -f "$PANE_DIR/${session}_${pane_id}.status" ]; then
        cat "$PANE_DIR/${session}_${pane_id}.status"; return
    fi
    if [ -f "$STATUS_DIR/${session}.status" ]; then
        cat "$STATUS_DIR/${session}.status"; return
    fi
    echo ""
}

# Agent name for a pane. Primary source: the plugin's .agent file (hook-based,
# claude/codex/devin). Fallback: process detection for agents the plugin does
# not track by default (maki, aider, opencode, ...), so any agent that shows up
# as a process in the pane is still identified. Presence only - no live state.
pane_agent() {
    local session="$1" pane_id="$2" pid ppid cmd name
    [ -f "$PANE_DIR/${session}_${pane_id}.agent" ] && { cat "$PANE_DIR/${session}_${pane_id}.agent"; return; }
    # Scan the pane's whole process subtree (descendants of the shell) for a
    # tracked agent. Covers agents run inside nvim --embed, tmux-in-tmux, etc.
    local root_pid
    root_pid=$(tmux list-panes -a -F "#{pane_pid} #{pane_id}" 2>/dev/null | awk -v p="$pane_id" '$2==p {print $1}')
    [ -n "$root_pid" ] || return
    # One ps snapshot: build the subtree, then match agent names in it.
    local snapshot
    snapshot=$(ps -eo pid=,ppid=,comm= 2>/dev/null)
    # Collect all pids in the subtree via BFS.
    local frontier="$root_pid" subtree="$root_pid" next="" pid
    while [ -n "$frontier" ]; do
        next=""
        for pid in $frontier; do
            local kids
            kids=$(printf '%s\n' "$snapshot" | awk -v p="$pid" '$2==p {print $1}')
            [ -n "$kids" ] && next="$next $kids"
        done
        frontier="${next# }"
        [ -n "$frontier" ] && subtree="$subtree $frontier"
    done
    # Match agent names against the subtree.
    local matched
    for name in maki aider codex devin opencode copilot cline; do
        matched=$(printf '%s\n' "$snapshot" | SUBTREE="$subtree" awk -v n="$name" '
            { pids[$1] = $3 }
            END {
                split(ENVIRON["SUBTREE"], s, " ")
                for (i in s) if (pids[s[i]] == n) { print n; exit }
            }')
        [ -n "$matched" ] && { printf '%s' "$matched"; return; }
    done
    echo ""
}

# One row per pane: type \t target \t icon \t label \t agent
emit_rows() {
    local fmt current_pane
    fmt=$(printf '#{session_name}\t#{window_index}\t#{pane_id}\t#{window_name}')
    current_pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null)
    tmux list-panes -a -F "$fmt" 2>/dev/null |
    while IFS=$'\t' read -r session win pane title; do
        local status agent status_label label marker
        status=$(pane_status "$session" "$pane")
        agent=$(pane_agent "$session" "$pane")
        status_label="${status:-idle}"
        [ -n "$agent" ] && status_label="$agent ($status)"
        # Use the window name if it's not just a number, else fall back to session.
        case "$title" in
            ''|*[!0-9]*) label="$title" ;;
            *)           label="$session" ;;
        esac
        marker=""
        [ "$pane" = "$current_pane" ] && { marker="*"; pin=0; } || pin=1
        printf '%s\t%s\t%s:%s\t%s\t%s %s [%s]\t%s\n' \
            "$pin" "pane" "$session" "$win" "$(status_icon "$status")" "$marker" "$label" "$status_label" "$agent"
    done | sort -t$'\t' -k1,1n -k4,4 -k5,5 | cut -f2- | column -t -s $'\t'
}

# Emit-only mode: used as fzf's input source and reload command.
if [ "${1:-}" = "--emit" ]; then
    emit_rows
    exit 0
fi

script_path=$(readlink -f "$0")

# The popup command: pipe rows into fzf, then pipe fzf's stdout (the selected
# line) into a handler that extracts the target and switches. All happens inside
# the popup shell, so we don't need display-popup to return anything.
fzf_cmd="bash $script_path --emit | fzf \
  --ansi --no-sort \
  --delimiter=' ' \
  --with-nth=4.. \
  --prompt=' agent  ' \
  --bind=ctrl-j:down,ctrl-k:up \
  --bind=\"ctrl-r:reload(bash $script_path --emit)\" \
  --layout=reverse --info=hidden | while read -r line; do [ -n \"\$line\" ] && { target=\$(printf '%s' \"\$line\" | awk '{print \$2}'); tmux switch-client -t \"\$target\" 2>/dev/null || tmux select-window -t \"\$target\"; }; done"

tmux display-popup -E -w 70% -h 50% -T " Agents " "$fzf_cmd"
