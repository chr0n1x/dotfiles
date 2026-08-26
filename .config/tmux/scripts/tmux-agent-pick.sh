#!/usr/bin/env bash
# Agent picker for tmux - replacement for the stock tmux-agent-status fzf
# switcher (prefix S). The stock switcher passes --listen=<unix socket> to
# fzf, which newer fzf builds reject ("invalid listen port"), so this is a
# plain fzf popup with no socket: works on any fzf version.
#
# Status comes from per-agent sources instead of hook files: claude reads its
# own session file (~/.claude/sessions/<pid>.json), everything else uses a
# child-process check (agent has children = working). Labels come from the
# agent's session name, falling back to window/session name. Status is shown
# only via the colored icon: green ● working, gray - idle, dim · no agent.

set -uo pipefail

CLAUDE_SESSIONS="$HOME/.claude/sessions"
MAKI_SESSIONS="$HOME/.maki/sessions"
AGENT_NAMES="claude maki aider codex devin opencode copilot cline"

# BFS over one ps snapshot; returns space-separated descendant pids of $1.
_pane_subtree() {
    local root_pid="$1" snapshot frontier subtree next pid kids
    snapshot=$(ps -eo pid=,ppid= 2>/dev/null)
    frontier="$root_pid"
    subtree="$root_pid"
    while [ -n "$frontier" ]; do
        next=""
        for pid in $frontier; do
            kids=$(printf '%s\n' "$snapshot" | awk -v p="$pid" '$2==p {print $1}')
            for k in $kids; do
                case " $subtree " in *" $k "*) : ;; *) subtree="$subtree $k"; next="$next $k" ;; esac
            done
        done
        frontier="${next# }"
    done
    printf '%s' "$subtree"
}

# "pid name" for the agent process in a pane, or empty. Scans the pane's whole
# process subtree (descendants of the shell) so agents run inside nvim --embed
# or tmux-in-tmux are still found.
pane_agent_pid() {
    local pane_id="$1" root_pid snapshot name pid matched
    root_pid=$(tmux list-panes -a -F "#{pane_pid} #{pane_id}" 2>/dev/null | awk -v p="$pane_id" '$2==p {print $1}')
    [ -n "$root_pid" ] || return
    local subtree
    subtree=$(_pane_subtree "$root_pid")
    snapshot=$(ps -eo pid=,ppid=,comm= 2>/dev/null)
    for name in $AGENT_NAMES; do
        matched=$(printf '%s\n' "$snapshot" | SUBTREE="$subtree" awk -v n="$name" '
            { pids[$1] = $3 }
            END {
                split(ENVIRON["SUBTREE"], s, " ")
                for (i in s) if (pids[s[i]] == n) { print s[i]; exit }
            }')
        [ -n "$matched" ] && { printf '%s %s' "${matched%% *}" "$name"; return; }
    done
}

# working | idle for a pane. claude uses its own session file status; all other
# agents use the child-process check (has children = working). No agent = idle.
pane_status() {
    local pane_id="$1" info pid name kids
    info=$(pane_agent_pid "$pane_id")
    [ -n "$info" ] || { echo idle; return; }
    pid="${info%% *}"
    name="${info##* }"
    if [ "$name" = claude ]; then
        local f="$CLAUDE_SESSIONS/$pid.json" status
        if [ -f "$f" ]; then
            status=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('status',''))" "$f" 2>/dev/null)
            case "$status" in
                running) echo working; return ;;
                '') : ;; # unreadable/missing field: fall through to child check
                *)       echo idle; return ;;
            esac
        fi
    fi
    kids=$(ps --ppid "$pid" -o pid= 2>/dev/null | grep -c .) || true
    [ "${kids:-0}" -gt 0 ] && { echo working; return; }
    echo idle
}

# Session name for a pane, or empty (caller falls back to window/session name).
session_label() {
    local pane_id="$1" info pid name f cwd sid title
    info=$(pane_agent_pid "$pane_id")
    [ -n "$info" ] || return
    pid="${info%% *}"
    name="${info##* }"
    case "$name" in
        claude)
            f="$CLAUDE_SESSIONS/$pid.json"
            [ -f "$f" ] || return
            python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('name',''))" "$f" 2>/dev/null
            ;;
        maki)
            cwd=$(tmux display-message -p '#{pane_current_path}' -t "$pane_id" 2>/dev/null)
            [ -n "$cwd" ] || return
            sid=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],''))" "$MAKI_SESSIONS/cwd_latest.json" "$cwd" 2>/dev/null)
            [ -n "$sid" ] || return
            f="$MAKI_SESSIONS/$sid.jsonl"
            [ -f "$f" ] || return
            title=$(grep '"t":"meta"' "$f" 2>/dev/null | tail -1 | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('title',''))" 2>/dev/null)
            printf '%s' "$title"
            ;;
    esac
}

status_icon() {
    local c='\033[0m'
    case "$1" in
        working) printf '\033[33m\xe2\x97\x86\033[0m' ;;  # yellow ◆ (agent working)
        idle)    printf '\033[32m\xe2\x97\x8f\033[0m' ;;  # green ● (agent idle, ready)
    esac
}

# One row per pane: pin \t pane \t session:win \t icon \t marker label \t agent
emit_rows() {
    local fmt current_pane
    fmt=$(printf '#{session_name}\t#{window_index}\t#{pane_id}\t#{window_name}\t#{pane_current_path}')
    current_pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null)
    tmux list-panes -a -F "$fmt" 2>/dev/null |
    while IFS=$'\t' read -r session win pane title cwd; do
        local info pid agent status label marker icon dir
        info=$(pane_agent_pid "$pane")
        if [ -n "$info" ]; then
            pid="${info%% *}"
            agent="${info##* }"
            status=$(pane_status "$pane")
        else
            agent=""
            status=""
        fi
        # Label: session name > window name (if non-numeric) > session name.
        label=$(session_label "$pane")
        case "$label" in
            '')
                case "$title" in
                    ''|*[!0-9]*) label="$title" ;;
                    *)           label="$session" ;;
                esac
                ;;
        esac
        if [ -n "$agent" ]; then
            icon=$(status_icon "$status")
        else
            icon=$(printf '\033[90m\xe2\x80\xa2\033[0m')
        fi
        # Show the working dir relative to $HOME for compactness.
        case "$cwd" in
            "$HOME")      dir="~" ;;
            "$HOME"/*)     dir="~${cwd#"$HOME"}" ;;
            *)            dir="$cwd" ;;
        esac
        marker=""
        if [ "$pane" = "$current_pane" ]; then marker="*"; pin=0; else pin=1; fi
        printf '%s\t%s\t%s:%s\t%s\t%s %s\t%s\t%s\n' \
            "$pin" "pane" "$session" "$win" "$icon" "$marker" "$label" "$(printf '\033[2m%s\033[0m' "$dir")" "$agent"
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
  --prompt=' search  ' \
  --bind=ctrl-j:down,ctrl-k:up \
  --bind=\"ctrl-r:reload(bash $script_path --emit)\" \
  --layout=reverse --info=hidden | while read -r line; do [ -n \"\$line\" ] && { target=\$(printf '%s' \"\$line\" | awk '{print \$2}'); tmux switch-client -t \"\$target\" 2>/dev/null || tmux select-window -t \"\$target\"; }; done"

tmux display-popup -E -w 70% -h 50% -T " Agents " "$fzf_cmd"
