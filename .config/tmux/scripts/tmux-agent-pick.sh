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
COPILOT_STATE="$HOME/.copilot/session-state"
AGENT_NAMES="claude maki aider codex devin opencode copilot cline"

# Session-state dir for a copilot pid, or empty. A copilot process can hold
# inuse.<pid>.lock files in several session dirs (resumed/switched sessions
# leave stale locks), so the lock alone is ambiguous. The active session is the
# one whose events.jsonl was most recently written; dirs with no events.jsonl
# (fresh, never-active) lose. If none have events yet, fall back to the newest
# lock. ls -t is used for mtime ordering so it works on both GNU and BSD.
copilot_session_dir() {
    local pid="$1" locks evs newest lock d
    [ -n "$pid" ] || return
    locks=$(find "$COPILOT_STATE" -maxdepth 2 -name "inuse.$pid.lock" 2>/dev/null)
    [ -n "$locks" ] || return
    # events.jsonl for each locked dir that has one.
    evs=$(printf '%s\n' "$locks" | while IFS= read -r lock; do
        d=$(dirname "$lock"); [ -f "$d/events.jsonl" ] && printf '%s\n' "$d/events.jsonl"
    done)
    if [ -n "$evs" ]; then
        newest=$(printf '%s\n' "$evs" | tr '\n' '\0' | xargs -0 ls -t 2>/dev/null | head -1)
        [ -n "$newest" ] && { dirname "$newest"; return; }
    fi
    # No events anywhere: newest lock wins.
    newest=$(printf '%s\n' "$locks" | tr '\n' '\0' | xargs -0 ls -t 2>/dev/null | head -1)
    [ -n "$newest" ] && dirname "$newest"
}

# "pid name" for the agent process in a pane, or empty. $1 is the pane's shell
# pid (pane_pid). One ps snapshot, one awk pass: computes the pane's whole
# process subtree (descendants of the shell) so agents run inside nvim --embed
# or tmux-in-tmux are still found, then returns the first pid whose command
# basename matches an agent name, honoring AGENT_NAMES priority order. Command
# basename is stripped so it works on both GNU (comm=name) and BSD/macOS
# (comm=/full/path) ps.
pane_agent_pid() {
    local root_pid="$1" snap="$2"
    [ -n "$root_pid" ] || return
    printf '%s\n' "$snap" | awk -v root="$root_pid" -v names="$AGENT_NAMES" '
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
# its own session file; copilot uses its per-session events.jsonl turn markers;
# maki and all other agents use the child-process check. No agent = idle.
pane_status() {
    local info="$1" cwd="${2:-}" snap="${3:-}" pid name kids
    [ -n "$info" ] || { echo idle; return; }
    pid="${info%% *}"
    name="${info##* }"
    # copilot exposes turn lifecycle in its per-session events.jsonl. Map the
    # pid -> session dir and read the last assistant.turn_start/turn_end marker:
    # a start with no following end means a turn is in progress = working. No
    # events file yet (fresh session) or a trailing end = idle. The child check
    # is unusable for copilot: it spawns helper subprocesses even when idle.
    if [ "$name" = copilot ]; then
        local dir ev state
        dir=$(copilot_session_dir "$pid")
        [ -n "$dir" ] || { echo unknown; return; }
        ev="$dir/events.jsonl"
        [ -f "$ev" ] || { echo idle; return; }
        state=$(tail -n 400 "$ev" 2>/dev/null | grep -oE '"assistant\.turn_(start|end)"' | tail -1)
        case "$state" in
            *turn_start*) echo working; return ;;
            *)            echo idle; return ;;
        esac
    fi
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
    # in a snapshot instead. Works on both GNU and BSD ps. For maki this catches
    # tool/bash execution (a real subprocess) but not pure text generation,
    # which maki does in-process via its model backend with no observable
    # per-pid signal.
    kids=$(printf '%s\n' "$snap" | awk -v p="$pid" '$2==p {c++} END {print c+0}')
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
            printf ' %s' "$title"
            ;;
        copilot)
            # Map this pane's copilot pid -> its exact session via the inuse
            # lock, then look up that session's summary by id. Mapping by cwd
            # instead would grab the newest session sharing the directory, which
            # shows a sibling session's title (or a stale one). Read-only open so
            # the live WAL db isn't disturbed.
            [ -f "$COPILOT_STORE" ] || return
            local dir sid
            dir=$(copilot_session_dir "$pid")
            [ -n "$dir" ] || return
            sid=$(basename "$dir")
            title=$(python3 -c "
import sqlite3,sys
try:
    c=sqlite3.connect('file:'+sys.argv[1]+'?mode=ro',uri=True)
    r=c.execute('SELECT summary FROM sessions WHERE id=?',(sys.argv[2],)).fetchone()
    print(r[0] if r and r[0] else '')
except Exception:
    print('')
" "$COPILOT_STORE" "$sid" 2>/dev/null)
            # No summary yet (fresh/unnamed session): fall back to the short
            # session id so the row is still identifiable.
            [ -n "$title" ] || title="${sid:0:8}"
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

# One tab-delimited row for a single pane. Reads ps_snap/win_w/current_pane
# from the enclosing emit_rows scope (inherited by the backgrounded subshell).
pane_row() {
    local session="$1" win="$2" pane="$3" title="$4" cwd="$5" panepid="$6"
    local info agent status label selected icon dir asession budget
    info=$(pane_agent_pid "$panepid" "$ps_snap")
    if [ -n "$info" ]; then
        agent="${info##* }"
        status=$(pane_status "$info" "$cwd" "$ps_snap")
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
        "$HOME")   dir="~" ;;
        "$HOME"/*) dir="~${cwd#"$HOME"}" ;;
        *)         dir="$cwd" ;;
    esac
    # Truncate the agent session title to fit the popup width (70% of terminal).
    if [ -n "$asession" ]; then
        budget=$(( ${#label} + ${#dir} + ${#agent} + 34 ))
        budget=$(( win_w * 90 / 100 - budget ))
        if [ "$budget" -lt 8 ]; then budget=8; fi
        if [ "${#asession}" -gt "$budget" ]; then asession="${asession:0:$((budget-1))}…"; fi
    fi
    printf '%s\t%s:%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$selected" "pane" "$session" "$win" "$icon" "$label" "$(printf '\033[2m%s\033[0m' "$dir")" "$(agent_color "$agent")" "$asession"
}

# One row per pane: pin \t pane \t session:win \t icon \t marker tmuxname \t dir \t agent \t agent-session-title
emit_rows() {
    local fmt current_pane ps_snap win_w tmpd n=0
    fmt=$(printf '#{session_name}\t#{window_index}\t#{pane_id}\t#{window_name}\t#{pane_current_path}\t#{pane_pid}')
    current_pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null)
    # One ps snapshot and one width lookup for the whole run, threaded into the
    # per-pane helpers below (previously each pane forked its own ps + tmux).
    ps_snap=$(ps -eo pid=,ppid=,comm= 2>/dev/null)
    win_w=$(tmux display-message -p '#{window_width}' 2>/dev/null) || win_w=180
    [ "$win_w" -ge 10 ] 2>/dev/null || win_w=180
    tmpd=$(mktemp -d "${TMPDIR:-/tmp}/tmux-agent-pick.XXXXXX") || return
    # Each pane's row is independent (agent detection, status, title lookups),
    # so compute them all in parallel. Zero-padded filenames keep the glob in
    # pane order, so the stable sort below reproduces the serial ordering.
    while IFS=$'\t' read -r session win pane title cwd panepid; do
        n=$((n + 1))
        pane_row "$session" "$win" "$pane" "$title" "$cwd" "$panepid" \
            > "$tmpd/$(printf '%03d' "$n")" &
    done < <(tmux list-panes -a -F "$fmt" 2>/dev/null)
    wait
    cat "$tmpd"/* 2>/dev/null > "$tmpd/all"
    # Order: active pane first, then panes with a detected agent (by window
    # index), then the rest. The pin column (field 1) is stripped last so the
    # sort keys below stay aligned; field 8 is the agent name (empty = none).
    { grep -a "^1	" "$tmpd/all" 2>/dev/null || true; \
      grep -av "^1	" "$tmpd/all" 2>/dev/null | sort -s -t$'\t' -k8,8r -k3,3n -k5,5; } \
      | cut -f2- > "$tmpd/ordered"
    # ordered lines: target \t win \t icon \t label \t dir \t agent \t title.
    # Column-align only the visible columns (win..title); keep the switch target
    # as a separate leading field joined by a single tab. fzf hides field 1 via
    # the tab delimiter, so the aligned block is shown verbatim. (Space-padding
    # from column -t would otherwise make --with-nth land on different offsets
    # for rows whose target width differs, e.g. a pane in the "scratch" session.)
    paste -d'\t' \
      <(cut -f1 "$tmpd/ordered") \
      <(cut -f2- "$tmpd/ordered" | column -t -s $'\t')
    rm -rf "$tmpd"
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
#
# Loading UX: the initial list is pre-rendered (needed to size the popup, see
# below), so it appears at once. On ctrl-r reload, --emit streams for a fraction
# of a second, keeping fzf's stdin open so its native "streaming input
# indicator" (the spinner shown by --info=inline-right) animates until the rows
# arrive. The header names the harnesses/paths being scanned and is cleared on
# the `load` event (fires when input finishes streaming).
export AGENT_PICK_HEADER="loading  •  claude ~/.claude  •  maki ~/.maki  •  copilot ~/.copilot"

# Size the popup to its content: render the rows once, measure the widest
# visible line (ANSI stripped, counted in display columns) and the row count,
# then derive width/height clamped to the client. fzf reads the same rows so
# what we measured is what's shown; ctrl-r reload still re-runs --emit live.
rows_file=$(mktemp "${TMPDIR:-/tmp}/tmux-agent-pick-rows.XXXXXX")
emit_rows > "$rows_file" 2>/dev/null

pop_w=""; pop_h=""
dims=$(python3 - "$rows_file" <<'PY' 2>/dev/null
import sys, re
esc = re.compile(r'\x1b\[[0-9;]*m')
maxw = n = 0
with open(sys.argv[1], encoding='utf-8', errors='replace') as fh:
    for line in fh:
        line = line.rstrip('\n')
        if not line:
            continue
        vis = line.split('\t', 1)[1] if '\t' in line else line
        maxw = max(maxw, len(esc.sub('', vis)))
        n += 1
print(maxw, n)
PY
)
if [ -n "$dims" ]; then
    content_w=${dims%% *}
    content_h=${dims##* }
    cw=$(tmux display-message -p '#{client_width}' 2>/dev/null); [ "$cw" -ge 20 ] 2>/dev/null || cw=200
    ch=$(tmux display-message -p '#{client_height}' 2>/dev/null); [ "$ch" -ge 8 ] 2>/dev/null || ch=50
    # +6 cols: border (2), fzf pointer gutter (2), a little slack for the
    # inline-right match count. +4 rows: border (2) + prompt line (1) + slack.
    pop_w=$(( content_w + 6 ))
    pop_h=$(( content_h + 4 ))
    [ "$pop_w" -lt 40 ] && pop_w=40
    [ "$pop_h" -lt 6 ]  && pop_h=6
    [ "$pop_w" -gt $(( cw - 2 )) ] && pop_w=$(( cw - 2 ))
    [ "$pop_h" -gt $(( ch - 2 )) ] && pop_h=$(( ch - 2 ))
fi

fzf_cmd="cat $rows_file | fzf \
  --ansi --no-sort --exact --cycle \
  --delimiter='\t' \
  --with-nth=2.. \
  --prompt=' search  ' \
  --header=\"\$AGENT_PICK_HEADER\" \
  --bind=ctrl-j:down,ctrl-k:up \
  --bind='load:change-header:' \
  --bind=\"ctrl-r:reload(bash $script_path --emit)\" \
  --info=inline-right | while read -r line; do [ -n \"\$line\" ] && { target=\$(printf '%s' \"\$line\" | awk '{print \$2}'); tmux switch-client -t \"\$target\" 2>/dev/null || tmux select-window -t \"\$target\"; }; done"

# display-popup -E blocks until the popup command exits, so clean up the
# rendered-rows file here rather than inside the popup pipeline (where a
# select-window switch can tear down the popup shell before it runs).
if [ -n "$pop_w" ] && [ -n "$pop_h" ]; then
    tmux display-popup -E -w "$pop_w" -h "$pop_h" -T " Agents " "$fzf_cmd"
else
    tmux display-popup -E -w 47% -h 33% -T " Agents " "$fzf_cmd"
fi
rm -f "$rows_file"
