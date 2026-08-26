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
COPILOT_STORE="$HOME/.copilot/session-store.db"
AGENT_NAMES="claude maki aider codex devin opencode copilot cline"

# "pid name" for the agent process in a pane, or empty. $1 is the pane's shell
# pid (pane_pid). One ps snapshot, one awk pass: computes the pane's whole
# process subtree (descendants of the shell) so agents run inside nvim --embed
# or tmux-in-tmux are still found, then returns the first pid whose command
# basename matches an agent name, honoring AGENT_NAMES priority order. Command
# basename is stripped so it works on both GNU (comm=name) and BSD/macOS
# (comm=/full/path) ps.
pane_agent_pid() {
    local root_pid="$1"
    [ -n "$root_pid" ] || return
    ps -eo pid=,ppid=,comm= 2>/dev/null | awk -v root="$root_pid" -v names="$AGENT_NAMES" '
        { pid[NR]=$1; ppid[$1]=$2; c=$3; sub(/.*\//,"",c); comm[$1]=c }
        END {
            n=split(names, order, " ")
            desc[root]=1
            changed=1
            while (changed) {
                changed=0
                for (i=1;i<=NR;i++) {
                    p=pid[i]
                    if (!(p in desc) && (ppid[p] in desc)) { desc[p]=1; changed=1 }
                }
            }
            for (k=1;k<=n;k++)
                for (i=1;i<=NR;i++) {
                    p=pid[i]
                    if ((p in desc) && comm[p]==order[k]) { print p, order[k]; exit }
                }
        }'
}

# working | idle | unknown. $1 is the precomputed "pid name" from pane_agent_pid
# (may be empty). $2 is the pane's cwd (reserved for future use). claude uses
# its own session file; copilot has no reliable status signal so returns unknown;
# all other agents use the child-process check. No agent = idle.
pane_status() {
    local info="$1" cwd="${2:-}" pid name kids
    [ -n "$info" ] || { echo idle; return; }
    pid="${info%% *}"
    name="${info##* }"
    [ "$name" = copilot ] && { echo unknown; return; }
    if [ "$name" = claude ]; then
        local f="$CLAUDE_SESSIONS/$pid.json" status
        if [ -f "$f" ]; then
            status=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('status',''))" "$f" 2>/dev/null)
            case "$status" in
                busy)    echo working; return ;;
                '')  : ;; # unreadable/missing field: fall through to child check
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
# $1 is the precomputed "pid name" from pane_agent_pid; $2 is the pane_id.
session_label() {
    local info="$1" pane_id="$2" pid name f sid title proj
    [ -n "$info" ] || return
    pid="${info%% *}"
    name="${info##* }"
    case "$name" in
        claude)
            # A user rename lives in the session file's "name" (nameSource is
            # absent or not "derived"). Prefer that; otherwise fall back to the
            # ai-title in the project jsonl (the session file's derived name is
            # not the real ai-title).
            f="$CLAUDE_SESSIONS/$pid.json"
            [ -f "$f" ] || return
            sid=$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
name=d.get('name','')
if name and d.get('nameSource','') != 'derived':
    print('\t'+name)          # leading tab flags a user-set name
else:
    print(d.get('sessionId','looked-up-below'))
" "$f" 2>/dev/null)
            case "$sid" in
                $'\t'*) printf '%s' "${sid#$'\t'}"; return ;;
            esac
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
        copilot)
            # No pid->session mapping exists; like maki, map cwd -> the most
            # recently updated session and use its summary. Read-only so the
            # live WAL db isn't disturbed.
            [ -f "$COPILOT_STORE" ] || return
            local cwd
            cwd=$(tmux display-message -p -t "$pane_id" '#{pane_current_path}' 2>/dev/null)
            [ -n "$cwd" ] || return
            title=$(python3 -c "
import sqlite3,sys
try:
    c=sqlite3.connect('file:'+sys.argv[1]+'?mode=ro',uri=True)
    r=c.execute('SELECT summary FROM sessions WHERE cwd=? AND summary IS NOT NULL AND summary<>\"\" ORDER BY updated_at DESC LIMIT 1',(sys.argv[2],)).fetchone()
    print(r[0] if r else '')
except Exception:
    print('')
" "$COPILOT_STORE" "$cwd" 2>/dev/null)
            printf ' %s' "$title"
            ;;
    esac
}

# $1=status (working|idle), $2=selected pane? (1/0). The current pane gets a
# star; other panes keep their shape. Color encodes agent state.
status_icon() {
    local star='★'
    case "$1:$2" in
        working:1) printf '\033[33m%s\033[0m' "$star" ;;   # yellow ★ (working, current)
        working:*) printf '\033[93m\xe2\x80\xa2\033[0m' ;; # bright yellow • (working)
        idle:1)    printf '\033[32m%s\033[0m' "$star" ;;   # green ★ (idle, current)
        idle:*)    printf '\033[32m\xe2\x9c\x93\033[0m' ;; # green ✓ (idle)
        unknown:1) printf '\033[90m%s\033[0m' "$star" ;;   # gray ★ (unknown, current)
        unknown:*) printf '\033[90m?\033[0m' ;;             # gray ? (unknown)
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
    fmt=$(printf '#{session_name}\t#{window_index}\t#{pane_id}\t#{window_name}\t#{pane_current_path}\t#{pane_pid}')
    current_pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null)
    tmux list-panes -a -F "$fmt" 2>/dev/null |
    while IFS=$'\t' read -r session win pane title cwd panepid; do
        local info agent status label selected icon dir
        info=$(pane_agent_pid "$panepid")
        if [ -n "$info" ]; then
            agent="${info##* }"
            status=$(pane_status "$info" "$cwd")
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
        asession=$(session_label "$info" "$pane")
        selected=0
        [ "$pane" = "$current_pane" ] && selected=1
        if [ -n "$agent" ]; then
            icon=$(status_icon "$status" "$selected")
        else
            icon=$(printf '\033[90m\xe2\x97\x8b\033[0m')
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
  --ansi --no-sort --exact \
  --delimiter=' ' \
  --with-nth=4.. \
  --prompt=' search  ' \
  --bind=ctrl-j:down,ctrl-k:up \
  --bind=\"ctrl-r:reload(bash $script_path --emit)\" \
  --info=hidden | while read -r line; do [ -n \"\$line\" ] && { target=\$(printf '%s' \"\$line\" | awk '{print \$2}'); tmux switch-client -t \"\$target\" 2>/dev/null || tmux select-window -t \"\$target\"; }; done"

tmux display-popup -E -w 70% -h 50% -T " Agents " "$fzf_cmd"
