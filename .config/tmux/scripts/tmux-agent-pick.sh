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
            printf '%s' "$title"
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
            printf '%s' "$title"
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
# Fields: pin, target(pane:<sess>), win, window-name-or-sessname, dir, icon,
# agent, title. The name+dir are carried per pane so emit_rows can build the
# window header from its first pane row.
pane_row() {
    local session="$1" win="$2" pane="$3" title="$4" cwd="$5" panepid="$6" cmd="${7:-}"
    local info agent status selected icon asession budget label dir
    info=$(pane_agent_pid "$panepid" "$ps_snap")
    if [ -n "$info" ]; then
        agent="${info##* }"
        status=$(pane_status "$info" "$cwd" "$ps_snap")
    else
        agent=""
        status=""
    fi
    asession=$(session_label "$info" "$pane")
    selected=0
    [ "$pane" = "$current_pane" ] && selected=1
    if [ -n "$agent" ]; then
        icon=$(status_icon "$status" "$selected")
    else
        icon=$(printf '\033[90m\xe2\x97\x8b\033[0m')
    fi
    # Window label: tmux window name (non-numeric) or session name.
    case "$title" in
        ''|*[!0-9]*) label="$title" ;;
        *)           label="$session" ;;
    esac
    # Show the working dir relative to $HOME for compactness, dimmed.
    case "$cwd" in
        "$HOME")   dir="~" ;;
        "$HOME"/*) dir="~${cwd#"$HOME"}" ;;
        *)         dir="$cwd" ;;
    esac
    dir=$(printf '\033[2m%s\033[0m' "$dir")
    # Truncate the agent session title to fit the popup width (90% of window).
    if [ -n "$asession" ]; then
        budget=$(( ${#agent} + 34 ))
        budget=$(( win_w * 90 / 100 - budget ))
        if [ "$budget" -lt 8 ]; then budget=8; fi
        if [ "${#asession}" -gt "$budget" ]; then asession="${asession:0:$((budget-1))}…"; fi
    fi
    # Build the row with a tab variable, not a printf format string: this bash
    # intermittently re-applies a tab-bearing format to surplus args when arg
    # count != specifier count, which mangles rows whose title is empty.
    local tab=$'\t'
    printf '%s\n' "${selected}${tab}pane:${session}${tab}${win}${tab}${label}${tab}${dir}${tab}${icon}${tab}$(agent_color "${agent:-}")${tab}${asession}${tab}${cmd}"
}

# Tree of rows: one header line per window (name only) followed by its pane
# lines (icon, path, agent-or-command). Pane-row fields before grouping:
# pin \t pane:<sess> \t win \t name \t dir \t icon \t agent \t title \t cmd.
emit_rows() {
    local fmt current_pane ps_snap win_w tmpd n=0
    fmt=$(printf '#{session_name}\t#{window_index}\t#{pane_id}\t#{window_name}\t#{pane_current_path}\t#{pane_pid}\t#{pane_current_command}')
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
    while IFS=$'\t' read -r session win pane title cwd panepid cmd; do
        n=$((n + 1))
        pane_row "$session" "$win" "$pane" "$title" "$cwd" "$panepid" "$cmd" \
            > "$tmpd/$(printf '%03d' "$n")" &
    done < <(tmux list-panes -a -F "$fmt" 2>/dev/null)
    wait
    cat "$tmpd"/* 2>/dev/null > "$tmpd/all"
    # Order: active pane first, then panes with a detected agent (by window
    # index), then the rest. The pin column (field 1) is stripped last so the
    # sort keys below stay aligned; field 3 is the window index, field 7 the
    # agent name (empty = none).
    { grep -a "^1	" "$tmpd/all" 2>/dev/null || true; \
      grep -av "^1	" "$tmpd/all" 2>/dev/null | sort -s -t$'\t' -k7,7r -k3,3n -k6,6; } \
      | cut -f2- > "$tmpd/ordered"
    # ordered lines: target \t win \t name \t dir \t icon \t agent \t title \t cmd.
    # Group by window (field 2) so each window's panes stay together even though
    # the active-pane-first sort can interleave windows. For each group emit a
    # header line then its pane lines. Header info: an agent name if any pane in
    # the window has one, else the first pane's current command. Final layout:
    # target \t win \t display. fzf hides fields 1-2 via --delimiter='\t'
    # --with-nth=3.. and shows only the display column; --switch/--kill read the
    # win field for both line types. The display keeps a fixed leading indent so
    # --with-nth lands on the same offset for every row regardless of target width.
    awk -F'\t' '
        function flush(   i) {
            if (n == 0) return
            # Window name goes below its panes; path and agent live on the pane
            # rows above it.
            for (i = 1; i <= n; i++) print pn[i]
            print "win:" nm ":" winidx "\t" winidx "\t" nm
            n = 0
        }
        {
            w = $2
            if (w != cur) { flush(); cur = w; winidx = w; nm = $3 }
            n++
            # Show the agent name if one is running, else fall back to the
            # pane current command (best-effort process detection).
            if ($6 != "") proc = $6; else proc = $8
            pn[n] = $1 "\t" $2 "\t      " $5 "\t" $4 "\t" proc "\t" $7
        }
        END { flush() }
    ' "$tmpd/ordered"
    rm -rf "$tmpd"
}

# Emit-only mode: used as fzf's input source and reload command.
if [ "${1:-}" = "--emit" ]; then
    emit_rows
    exit 0
fi

# Switch mode: given a full emit line, switch the client to that window.
# Field 1 (tab-delimited) is "pane:<session>" for pane rows or
# "win:<session>:<index>" for window header rows; field 2 is the window index
# on both line types. Using "<session>:<window>" makes cross-session switching
# work (a bare window index can't resolve a window in another session).
if [ "${1:-}" = "--switch" ]; then
    line="${2:-}"
    target=$(printf '%s' "$line" | cut -f1)
    case "$target" in
        win:*) sess=${target#win:}; sess=${sess%%:*} ;;  # drop the :<index> tail
        *)     sess=${target#pane:} ;;
    esac
    win=$(printf '%s' "$line" | cut -f2)
    [ -n "$win" ] && {
        tmux switch-client -t "${sess}:${win}" 2>/dev/null \
            || tmux select-window -t "$win" 2>/dev/null
    }
    exit 0
fi

# Kill mode: given a full emit line, confirm then kill that window. Both row
# types resolve to their window (pane rows kill the window containing the
# pane), matching the pre-tree behavior. Run via fzf's execute() (not
# execute-silent) so we have a tty to prompt on.
if [ "${1:-}" = "--kill" ]; then
    line="${2:-}"
    target=$(printf '%s' "$line" | cut -f1)
    case "$target" in
        win:*) sess=${target#win:}; sess=${sess%%:*} ;;  # drop the :<index> tail
        *)     sess=${target#pane:} ;;
    esac
    win=$(printf '%s' "$line" | cut -f2)
    [ -z "$win" ] && exit 0
    printf 'Kill window %s:%s? [y/N] ' "$sess" "$win" > /dev/tty
    read -r ans < /dev/tty
    case "$ans" in
        [yY]*) tmux kill-window -t "${sess}:${win}" 2>/dev/null ;;
    esac
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
# The header names the harnesses/paths being scanned while loading, then
# switches to a key legend on the `load` event (fires when input finishes
# streaming). The legend line is already reserved during loading, so swapping
# it in costs no extra popup height.
export AGENT_PICK_HEADER="loading  •  claude ~/.claude  •  maki ~/.maki  •  copilot ~/.copilot"
legend="enter ⇄    esc ⊘    ^r ↻    ^k ⊗"
export legend
min_popup_width=80

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
        parts = line.split('\t')
        # Fields 3+ are the display column (fields 1-2 are the hidden target/win);
        # fzf joins them with tabs for display, so measure the joined remainder.
        vis = '\t'.join(parts[2:]) if len(parts) > 2 else line
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
    min_w=$min_popup_width
    [ "$min_w" -lt $(( cw / 3 )) ] && min_w=$(( cw / 3 ))
    # +6 cols: border (2), fzf pointer gutter (2), a little slack for the
    # inline-right match count. +7 rows: tmux border (2) + prompt (1) + header
    # (1) + fzf bottom legend border (1) + slack (2).
    pop_w=$(( content_w + 6 ))
    pop_h=$(( content_h + 7 ))
    # Give the popup ~1.5x vertical breathing room over the bare content height.
    pop_h=$(( pop_h * 3 / 2 ))
    [ "$pop_w" -lt "$min_w" ] && pop_w=$min_w
    [ "$pop_w" -lt 40 ] && pop_w=40
    [ "$pop_h" -lt 6 ]  && pop_h=6
    [ "$pop_w" -gt $(( cw - 2 )) ] && pop_w=$(( cw - 2 ))
    [ "$pop_h" -gt $(( ch - 2 )) ] && pop_h=$(( ch - 2 ))
fi

# Remember where the client is now so Esc can restore it after previewing.
orig_target=$(tmux display-message -p '#{session_name}:#{window_index}' 2>/dev/null)

fzf_cmd="cat $rows_file | fzf \
  --ansi --no-sort --exact --cycle \
  --delimiter='\t' \
  --with-nth=3.. \
  --prompt=' search  ' \
  --header=\"\$AGENT_PICK_HEADER\" \
  --bind=ctrl-j:down \
  --bind='load:change-header:' \
  --bind=\"focus:execute-silent(bash $script_path --switch {})\" \
  --bind=\"ctrl-k:execute(bash $script_path --kill {})+reload(bash $script_path --emit)\" \
  --bind=\"esc:execute-silent(tmux switch-client -t '$orig_target')+abort\" \
  --bind=\"ctrl-r:reload(bash $script_path --emit)\" \
  --info=inline-right \
  --header-first \
  --border=bottom \
  --border-label=\"  \$legend  \" \
  --border-label-pos=center \
  --color=header:8,border:8,label:8 | while read -r line; do [ -n \"\$line\" ] && bash $script_path --switch \"\$line\"; done"

# display-popup -E blocks until the popup command exits, so clean up the
# rendered-rows file here rather than inside the popup pipeline (where a
# select-window switch can tear down the popup shell before it runs).
# tmux has no title-alignment flag. Center the title by padding it to the
# popup's inner width, but pad with the border's horizontal line char (not
# spaces, which would erase the top border) so the border stays continuous.
title=" tmux windows "
if [ -n "$pop_w" ] && [ -n "$pop_h" ]; then
    eff_w=$pop_w
else
    cw=$(tmux display-message -p '#{client_width}' 2>/dev/null); [ "$cw" -ge 20 ] 2>/dev/null || cw=200
    eff_w=$(( cw * 47 / 100 ))
    min_w=$min_popup_width
    [ "$min_w" -lt $(( cw / 3 )) ] && min_w=$(( cw / 3 ))
    [ "$eff_w" -lt "$min_w" ] && eff_w=$min_w
    [ "$eff_w" -gt $(( cw - 2 )) ] && eff_w=$(( cw - 2 ))
fi
pad=$(( (eff_w - 2 - ${#title}) / 2 ))
[ "$pad" -lt 1 ] && pad=1
line=$(printf '─%.0s' $(seq 1 "$pad"))
ctitle="${line}${title}${line}"
if [ -n "$pop_w" ] && [ -n "$pop_h" ]; then
    tmux display-popup -E -w "$pop_w" -h "$pop_h" \
        -e "AGENT_PICK_HEADER=$AGENT_PICK_HEADER" -e "legend=$legend" \
        -T "$ctitle" "$fzf_cmd"
else
    tmux display-popup -E -w "$eff_w" -h 33% \
        -e "AGENT_PICK_HEADER=$AGENT_PICK_HEADER" -e "legend=$legend" \
        -T "$ctitle" "$fzf_cmd"
fi
rm -f "$rows_file"
