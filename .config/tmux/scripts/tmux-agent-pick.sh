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
CLAUDE_PROJECTS="$HOME/.claude/projects"
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
    # Portable child check: BSD ps (macOS) has no --ppid, so count ppid matches
    # in a snapshot instead. Works on both GNU and BSD ps.
    kids=$(ps -eo pid=,ppid= 2>/dev/null | awk -v p="$pid" '$2==p {c++} END {print c+0}')
    [ "${kids:-0}" -gt 0 ] && { echo working; return; }
    echo idle
}

# Session name for a pane, or empty (caller falls back to window/session name).
session_label() {
    local pane_id="$1" info pid name f sid title proj
    info=$(pane_agent_pid "$pane_id")
    [ -n "$info" ] || return
    pid="${info%% *}"
    name="${info##* }"
    case "$name" in
        claude)
            # Session file maps pid -> sessionId; the real (ai-)title lives in
            # the project jsonl, not in the session file's derived "name".
            f="$CLAUDE_SESSIONS/$pid.json"
            [ -f "$f" ] || return
            sid=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('sessionId',''))" "$f" 2>/dev/null)
            [ -n "$sid" ] || return
            proj=$(find "$CLAUDE_PROJECTS" -maxdepth 2 -name "$sid.jsonl" 2>/dev/null | head -1)
            [ -n "$proj" ] || return
            title=$(grep '"ai-title"' "$proj" 2>/dev/null | tail -1 | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('aiTitle',''))" 2>/dev/null)
            printf '%s' "$title"
            ;;
        maki)
            # Session id is the jsonl filename stem. cwd_latest.json maps
            # cwd -> sid of the most recent session started in that dir.
            local cwd
            cwd=$(tmux display-message -p -t "$pane_id" '#{pane_current_path}' 2>/dev/null)
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

# $1=status (working|idle), $2=selected pane? (1/0). The current pane gets a
# star; other panes keep their shape. Color encodes agent state.
status_icon() {
    local star='★'
    case "$1:$2" in
        working:1) printf '\033[33m%s\033[0m' "$star" ;;  # yellow ★ (working, current)
        working:*) printf '\033[33m\xe2\x97\x86\033[0m' ;;  # yellow ◆ (working)
        idle:1)    printf '\033[32m%s\033[0m' "$star" ;;  # green ★ (idle, current)
        idle:*)    printf '\033[32m\xe2\x97\x8f\033[0m' ;;  # green ● (idle)
    esac
}

# Per-agent name color.
agent_color() {
    case "$1" in
        claude)   printf '\033[38;2;240;150;95m%s\033[0m' "$1" ;;  # light rust
        maki)     printf '\033[38;2;110;185;240m%s\033[0m' "$1" ;;  # light cerulean
        copilot)  printf '\033[38;2;170;120;255m%s\033[0m' "$1" ;;  # purple
        *)        printf '%s' "$1" ;;
    esac
}

# One row per pane: pin \t pane \t session:win \t icon \t marker tmuxname \t dir \t agent \t agent-session-title
emit_rows() {
    local fmt current_pane
    fmt=$(printf '#{session_name}\t#{window_index}\t#{pane_id}\t#{window_name}\t#{pane_current_path}')
    current_pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null)
    tmux list-panes -a -F "$fmt" 2>/dev/null |
    while IFS=$'\t' read -r session win pane title cwd; do
        local info pid agent status label selected icon dir
        info=$(pane_agent_pid "$pane")
        if [ -n "$info" ]; then
            pid="${info%% *}"
            agent="${info##* }"
            status=$(pane_status "$pane")
        else
            agent=""
            status=""
        fi
        # Second column: tmux window name (non-numeric) or session name.
        # Last column: agent session title, if the agent has one.
        case "$title" in
            ''|*[!0-9]*) label="$title" ;;
            *)           label="$session" ;;
        esac
        asession=$(session_label "$pane")
        selected=0
        [ "$pane" = "$current_pane" ] && selected=1
        if [ -n "$agent" ]; then
            icon=$(status_icon "$status" "$selected")
        else
            icon=$(printf '\033[90m\xe2\x80\xa2\033[0m')
        fi
        # Show the working dir relative to $HOME for compactness.
        case "$cwd" in
            "$HOME")      dir="~" ;;
            "$HOME"/*)     dir="~${cwd#"$HOME"}" ;;
            *)            dir="$cwd" ;;
        esac
        # Truncate the agent session title to fit the popup width. The popup
        # is 70% of the terminal, so compute a budget from the actual width.
        if [ -n "$asession" ]; then
            local budget=$(( ${#label} + ${#dir} + ${#agent} + 34 ))
            local w
            w=$(tmux display-message -p '#{window_width}' 2>/dev/null) || w=180
            [ "$w" -ge 10 ] 2>/dev/null || w=180
            budget=$(( ${w} * 7 / 10 - budget ))
            if [ "$budget" -lt 8 ]; then budget=8; fi
            if [ "${#asession}" -gt "$budget" ]; then asession="${asession:0:$((budget-1))}…"; fi
        fi
        printf '%s\t%s:%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$selected" "pane" "$session" "$win" "$icon" "$label" "$(printf '\033[2m%s\033[0m' "$dir")" "$(agent_color "$agent")" "$asession"
    done > /tmp/.tmux-agent-pick.$$
    # Order: active pane first, then panes with a detected agent (by window
    # index), then the rest. The pin column (field 1) is stripped last so the
    # sort keys below stay aligned; field 8 is the agent name (empty = none).
    { grep -a "^1	" /tmp/.tmux-agent-pick.$$ 2>/dev/null || true; \
      grep -av "^1	" /tmp/.tmux-agent-pick.$$ 2>/dev/null | sort -t$'\t' -k8,8r -k3,3n -k5,5; } \
      | cut -f2- | column -t -s $'\t'
    rm -f /tmp/.tmux-agent-pick.$$
}

# Emit-only mode: used as fzf's input source and reload command.
if [ "${1:-}" = "--emit" ]; then
    emit_rows
    exit 0
fi

# Portable realpath: macOS readlink lacks -f. Resolve symlinks by hand.
resolve_path() {
    local p="$1"
    while [ -h "$p" ]; do
        local dir link
        dir=$(cd -P "$(dirname "$p")" >/dev/null 2>&1 && pwd)
        link=$(readlink "$p")
        case "$link" in /*) p="$link" ;; *) p="$dir/$link" ;; esac
    done
    printf '%s' "$p"
}
script_path=$(resolve_path "$0")

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
  --info=hidden | while read -r line; do [ -n \"\$line\" ] && { target=\$(printf '%s' \"\$line\" | awk '{print \$2}'); tmux switch-client -t \"\$target\" 2>/dev/null || tmux select-window -t \"\$target\"; }; done"

tmux display-popup -E -w 70% -h 50% -T " Agents " "$fzf_cmd"
