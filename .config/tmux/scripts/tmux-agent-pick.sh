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
# only via the colored icon: blue ● working, green ✓ idle, gray ? unknown,
# gray • no agent (the current pane's icon is a star ★).

set -uo pipefail

CLAUDE_SESSIONS="$HOME/.claude/sessions"
CLAUDE_PROJECTS="$HOME/.claude/projects"
MAKI_SESSIONS="$HOME/.maki/sessions"
COPILOT_STORE="$HOME/.copilot/session-store.db"
COPILOT_STATE="$HOME/.copilot/session-state"
PI_SESSIONS="$HOME/.pi/agent/sessions"
# pig (the Go wrapper around pi) keeps its own config root and never reads ~/.pi.
PIG_SESSIONS="$HOME/.pig/agent/sessions"
# The agent_pick python package sits next to this script. Resolve the real dir
# (this file is a stow symlink) so cli.py is found regardless of how the script
# was invoked.
SCRIPT_DIR=$(cd -P "$(dirname "$0")" >/dev/null 2>&1 && pwd)
AGENT_CLI="$SCRIPT_DIR/agent_pick/cli.py"
# Fixed picker column widths, so the columns to their right sit at the same
# spot every time the popup opens instead of following the longest entry.
# DIR_COLS fits a fish-shortened path like ~/C/A/adobe-chat-harness; longer
# ones are cut from the left. AGENT_COLS is the longest name in AGENT_NAMES
# (opencode); a longer pane command still widens the column.
DIR_COLS=24
AGENT_COLS=8
# A pane can run more than one agent (e.g. maki and pig in one nvim pane).
# The column shows up to this many names, then a dim "+N" for the rest, so a
# pane with several agents doesn't blow out the column width.
AGENT_MAX_SHOWN=2
AGENT_NAMES="claude maki aider codex devin opencode copilot cline pi pig crush"
# Python for json/sqlite lookups. Override with PYTHON_BIN to point at a
# specific interpreter (e.g. a pyenv shim or /usr/bin/python3 where the default
# python3 is something else). Empty = no python: labels are skipped and status
# falls back to the child-process check; column alignment degrades to tab stops.
# Minimum python: the resolver only uses the 3.x stdlib (json, glob, re, os,
# sqlite3), all of which are stable from 3.0. _python_ok exits 0 when the
# interpreter at $1 runs and is python 3.x (anything 2.x fails). Found by
# walking $PATH in-shell (a $(command -v) subshell costs a fork); a pyenv/conda
# shim earlier on PATH wins, with a /usr/bin/python3 fallback if the walk finds
# nothing usable.
_python_ok() {
    [ -x "$1" ] || return 1
    "$1" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' 2>/dev/null
}
PYTHON_BIN="${PYTHON_BIN:-}"
if [ -z "$PYTHON_BIN" ]; then
    _ifs=$IFS; IFS=:
    for _d in $PATH; do
        _python_ok "$_d/python3" && { PYTHON_BIN="$_d/python3"; break; }
    done
    IFS=$_ifs; unset _ifs _d
    [ -n "$PYTHON_BIN" ] || { _python_ok /usr/bin/python3 && PYTHON_BIN=/usr/bin/python3; }
fi
# A bad override (missing, or below the minimum) counts as no python: labels are
# skipped and status falls back to the child-process check.
[ -n "$PYTHON_BIN" ] && _python_ok "$PYTHON_BIN" || PYTHON_BIN=""

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

# Agent processes for every pane, from one ps snapshot ("pid ppid comm" on
# stdin) and one awk pass. $1 is the space-separated list of pane shell pids.
# For each pid, walks its whole process subtree (so agents run inside nvim
# --embed or tmux-in-tmux are still found) and collects every distinct agent in
# it, in AGENT_NAMES priority order. Command basename is stripped so it works
# on both GNU (comm=name) and BSD/macOS (comm=/full/path) ps. Prints one
# "<shell pid>|<name1> <pid1> <name2> <pid2>..." line per input pid, in order,
# with nothing after the | when the pane runs no agent. Pairs are name-pid so
# the label resolver can look up each agent's session name (labels are per-pid);
# the first pair is the primary agent (drives the status/icon).
pane_agents() {
    awk -v roots="$1" -v names="$AGENT_NAMES" '
        { pid[NR]=$1; c=$3; sub(/.*\//,"",c); comm[$1]=c; kids[$2]=kids[$2] " " $1 }
        END {
            n=split(names, order, " ")
            m=split(roots, R, " ")
            for (r=1; r<=m; r++) {
                root=R[r]
                split("", desc)
                desc[root]=1; q[1]=root; qh=1; qt=1
                while (qh<=qt) {
                    k=split(kids[q[qh++]], ch, " ")
                    for (i=1; i<=k; i++)
                        if (!(ch[i] in desc)) { desc[ch[i]]=1; q[++qt]=ch[i] }
                }
                # Collect every distinct agent in the subtree as a name-pid pair,
                # in priority order. The first pair is the primary agent (its pid
                # drives the status/icon); the rest feed the label resolver and
                # the display column.
                pairs=""
                for (o=1; o<=n; o++) {
                    for (i=1; i<=NR; i++) {
                        if ((pid[i] in desc) && comm[pid[i]]==order[o]) {
                            pairs = (pairs=="") ? order[o] " " pid[i] : pairs " " order[o] " " pid[i]
                            break
                        }
                    }
                }
                print root "|" pairs
            }
        }'
}

# Status + label for every pane, resolved by the agent_pick python package in
# agent_pick/ next to this script. One python run for the whole list (each
# python start costs ~50-100ms; per-pane lookups used to start it 2-3 times per
# pane). The ps snapshot is passed in AGENT_PICK_SNAP; the session roots in
# argv. See agent_pick/cli.py for the stdin/stdout contract and agent_pick/core.py
# for the per-agent logic (tested in tests/test_agent_pick.py).

# Kill the whole process subtree rooted at a pane's shell pid, so agents and
# long-lived children (nvim --embed, podman-compose, ssh) don't outlive the
# pane. $1 is the pane id. Snapshots ps once, walks descendants of the shell
# pid, and kills them deepest-first (SIGTERM, then SIGKILL on stragglers). The
# caller still runs tmux kill-pane/kill-window afterwards to remove the pane
# from tmux's bookkeeping; by then the processes are already gone.
kill_pane_tree() {
    local pane="$1" shell_pid snap pids pid
    shell_pid=$(tmux display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null)
    [ -n "$shell_pid" ] || return
    snap=$(ps -eo pid=,ppid= 2>/dev/null)
    # All descendants of the shell pid (excluding the shell itself), deepest
    # first so children die before their parents.
    pids=$(printf '%s\n' "$snap" | awk -v root="$shell_pid" '
        { pid[NR]=$1; ppid[$1]=$2 }
        END {
            desc[root]=1; changed=1
            while (changed) { changed=0
                for (i=1;i<=NR;i++) { p=pid[i]; if (!(p in desc) && (ppid[p] in desc)) { desc[p]=1; changed=1 } }
            }
            # collect descendants, sort by depth (deeper = more ancestors = first)
            for (i=1;i<=NR;i++) { p=pid[i]; if ((p in desc) && p!=root) {
                d=0; q=p; while (q!=root && q!="") { d++; q=ppid[q] }; depth[p]=d } }
            n=0
            for (p in depth) { n++; list[n]=p }
            # simple insertion sort by depth desc
            for (i=2;i<=n;i++) { v=list[i]; j=i-1
                while (j>=1 && depth[list[j]]<depth[v]) { list[j+1]=list[j]; j-- }
                list[j+1]=v }
            for (i=1;i<=n;i++) print list[i]
        }')
    [ -n "$pids" ] || return
    # SIGTERM the subtree, deepest first.
    printf '%s\n' "$pids" | while IFS= read -r pid; do
        kill -TERM "$pid" 2>/dev/null
    done
    # Give them a moment, then SIGKILL anything still alive.
    sleep 0.3
    printf '%s\n' "$pids" | while IFS= read -r pid; do
        kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
    done
}


# working | idle | unknown, without python (agent_pick/core.py handles the
# python case). $1 is "pid name" from pane_agents, $2 the pane's cwd (unused),
# $3 the ps snapshot. copilot reads its per-session events.jsonl turn markers
# (the child check is unusable: it keeps helper subprocesses when idle). pig
# keeps a node child alive the whole time, and its turn state needs json, so it
# is unknown here. Everything else uses the child-process check.
# Status for a single agent (python-free). $1=name $2=pid $3=ps-snapshot.
# Mirrors core.status() for the no-python fallback path.
one_status() {
    local name="$1" pid="$2" snap="${3:-}" kids dir ev state
    if [ "$name" = pig ]; then
        echo unknown
        return
    fi
    # A start with no following end means a turn is in progress = working. No
    # events file yet (fresh session) or a trailing end = idle.
    if [ "$name" = copilot ]; then
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
    # Portable child check: BSD ps (macOS) has no --ppid, so count ppid matches
    # in a snapshot instead. Works on both GNU and BSD ps.
    kids=$(printf '%s\n' "$snap" | awk -v p="$pid" '$2==p {c++} END {print c+0}')
    [ "${kids:-0}" -gt 0 ] && { echo working; return; }
    echo idle
}

# Aggregate a pane's name-pid pairs into one icon state (python-free mirror of
# core.reduce_status): any working -> working, else any idle -> idle, else
# unknown. $1=pairs string, $3=ps snapshot.
pane_status() {
    local info="$1" snap="${3:-}" name pid
    [ -n "$info" ] || { echo idle; return; }
    local working=0 idle=0
    # Walk the pairs: for each name token, the next token is its pid.
    local first=1
    for tok in $info; do
        if [ "$first" -eq 1 ]; then
            name="$tok"; first=0; continue
        fi
        pid="$tok"; first=1
        case "$(one_status "$name" "$pid" "$snap")" in
            working) working=1 ;;
            idle)    idle=1 ;;
        esac
    done
    if [ "$working" -eq 1 ]; then echo working; return; fi
    if [ "$idle" -eq 1 ]; then echo idle; return; fi
    echo unknown
}


# $1=status (working|idle), $2=selected pane? (1/0). The current pane gets a
# star; other panes keep their shape. Color encodes agent state.
# Working status color: vibrant blue #3d9bff, matching Neovim's lualine
# AgentDotWorking highlight (harness-decorators/agent-display.lua) so a working
# agent reads the same in the tmux picker and in the editor.
WORKING_COLOR=$'\033[38;2;61;155;255m'
status_icon() {
    local star='★'
    case "$1:$2" in
        working:1) printf '%s%s\033[0m' "$WORKING_COLOR" "$star" ;; # blue ★ (working, current)
        working:*) printf '%s\xe2\x97\x8f\033[0m' "$WORKING_COLOR" ;; # blue ● (working, matches lualine)
        idle:1)    printf '\033[32m%s\033[0m' "$star" ;;   # green ★ (idle, current)
        idle:*)    printf '\033[32m\xe2\x9c\x93\033[0m' ;; # green ✓ (idle)
        unknown:1) printf '\033[90m%s\033[0m' "$star" ;;   # gray ★ (unknown, current)
        unknown:*) printf '\033[90m?\033[0m' ;;             # gray ? (unknown)
    esac
}

# Color one agent name.
agent_color_one() {
    case "$1" in
        claude)   printf '\033[38;2;240;150;95m%s\033[0m' "$1" ;;  # light rust
        maki)     printf '\033[38;2;110;185;240m%s\033[0m' "$1" ;;  # light cerulean
        copilot)  printf '\033[38;2;170;120;255m%s\033[0m' "$1" ;;  # purple
        pi)       printf '\033[38;2;255;255;255m%s\033[0m' "$1" ;;  # white (pi.dev logo)
        pig)      printf '\033[38;2;61;220;110m%s\033[0m' "$1" ;;  # green (#3ddc6e, nvim idle checkmark)
        crush)    printf '\033[38;2;255;96;255m%s\033[0m' "$1" ;;  # charm magenta
        *)        printf '%s' "$1" ;;
    esac
}
# Color a space-separated list of agent names, each in its own color, comma-
# separated, capped to $AGENT_MAX_SHOWN shown names with a dim " (N more)" for
# the rest so the column stays bounded (e.g. "maki, pi (2 more)").
agent_color() {
    local names="$1" out="" n shown=0 extra=0 sep=""
    local dim=$'\033[2m' rst=$'\033[0m'
    local max="${AGENT_MAX_SHOWN:-2}"
    for n in $names; do
        shown=$((shown + 1))
        if [ "$shown" -le "$max" ]; then
            out="$out$sep$(agent_color_one "$n")"
            sep=", "
        else
            extra=$((extra + 1))
        fi
    done
    if [ "$extra" -gt 0 ]; then
        out="$out${dim} ($extra more)${rst}"
    fi
    printf '%s' "$out"
}

# One tab-delimited row for a single pane. $7-$9 are its agent name, status
# and session label (all empty when the pane runs no agent). Reads
# win_w/current_pane from the enclosing emit_rows scope.
# Fields: pin, target(pane:<sess>), win, window-name-or-sessname, dir, icon,
# agent, title. The name+dir are carried per pane so emit_rows can build the
# window header from its first pane row.
pane_row() {
    local session="$1" win="$2" pane="$3" title="$4" cwd="$5" cmd="${6:-}"
    local agent="${7:-}" status="${8:-}" asession="${9:-}"
    local selected icon budget label dir
    selected=0
    [ "$pane" = "$current_pane" ] && selected=1
    if [ -n "$agent" ]; then
        icon=$(status_icon "$status" "$selected")
    else
        # No agent: a gray small filled dot, the same visual family as the
        # working ● / idle ✓ / unknown ? icons (a dot, not a hollow ring).
        icon=$(printf '\033[90m\xe2\x80\xa2\033[0m')
    fi
    # Window label: tmux window name (non-numeric) or session name.
    case "$title" in
        ''|*[!0-9]*) label="$title" ;;
        *)           label="$session" ;;
    esac
    # Show the working dir relative to $HOME for compactness, dimmed, with every
    # parent dir cut to its first letter (fish-style: ~/C/A/dory-deploy) so one
    # long path can't widen the column for every row. Dot-dirs keep the letter
    # after the dot (~/.c/nvim). Pure parameter expansion: no subshells.
    case "$cwd" in
        "$HOME")   dir="~" ;;
        "$HOME"/*) dir="~${cwd#"$HOME"}" ;;
        *)         dir="$cwd" ;;
    esac
    local short="" part rest="$dir"
    while [[ "$rest" == */* ]]; do
        part=${rest%%/*}
        rest=${rest#*/}
        case "$part" in
            ''|'~') short="$short$part/" ;;
            .*)     short="$short${part:0:2}/" ;;
            *)      short="$short${part:0:1}/" ;;
        esac
    done
    dir="$short$rest"
    # Longer than the fixed column (a long last dir name): keep the end.
    [ "${#dir}" -gt "$DIR_COLS" ] && dir="…${dir: -$((DIR_COLS - 1))}"
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
    printf '%s\n' "${selected}${tab}pane:${session}:${pane}${tab}${win}${tab}${label}${tab}${dir}${tab}${icon}${tab}$(agent_color "${agent:-}")${tab}${asession}${tab}${cmd}"
}

# Tree of rows: one header line per window (name only), then its pane lines
# below with ├─/└─ tree connectors on the left (htop-style).
# Pane-row fields before grouping:
# pin \t pane:<sess> \t win \t name \t dir \t icon \t agent \t title \t cmd.
emit_rows() {
    local fmt current_pane ps_snap win_w panes roots="" agents results="" input=""
    local session win pane title cwd panepid cmd line info st lb
    local tab=$'\t' us=$'\037'
    fmt=$(printf '#{session_name}\t#{window_index}\t#{pane_id}\t#{window_name}\t#{pane_current_path}\t#{pane_pid}\t#{pane_current_command}')
    # One ps snapshot, one width lookup, one agent scan and one python run for
    # the whole list: every process start costs tens of ms, so per-pane lookups
    # were most of the popup's open time.
    ps_snap=$(ps -eo pid=,ppid=,comm= 2>/dev/null)
    read -r current_pane win_w <<<"$(tmux display-message -p '#{pane_id} #{window_width}' 2>/dev/null)"
    [ "$win_w" -ge 10 ] 2>/dev/null || win_w=180
    panes=$(tmux list-panes -a -F "$fmt" 2>/dev/null)
    while IFS=$'\t' read -r session win pane title cwd panepid cmd; do
        roots="$roots $panepid"
    done <<<"$panes"
    agents=$(printf '%s\n' "$ps_snap" | pane_agents "$roots")
    # The lists below are zipped line by line on separate fds (no associative
    # arrays: macOS /bin/bash is 3.2). Fields that can be empty are joined with
    # \037, not tab: tab is IFS whitespace, so read would collapse empty fields.
    if [ -n "$PYTHON_BIN" ] && [ -f "$AGENT_CLI" ]; then
        while IFS=$'\t' read -r session win pane title cwd panepid cmd <&3 && IFS= read -r line <&4; do
            info=${line#*|}
            # info = "<name1> <pid1> <name2> <pid2>..." (name-pid pairs, priority
            # order). The python resolver takes ALL pairs: status/icon from the
            # primary (first pair), and the label is the shortest non-empty
            # session name across every agent, so a pane whose primary has no
            # label still shows one from a sibling agent.
            input="$input${pane}${tab}${info}${tab}${cwd}"$'\n'
        done 3<<<"$panes" 4<<<"$agents"
        # cli.py imports agent_pick.core, so the package dir (SCRIPT_DIR) must
        # be on the path; PYTHONPATH makes the import resolve without a cwd.
        results=$(printf '%s' "$input" | AGENT_PICK_SNAP="$ps_snap" \
            PYTHONPATH="$SCRIPT_DIR" "$PYTHON_BIN" "$AGENT_CLI" \
            "$CLAUDE_SESSIONS" "$CLAUDE_PROJECTS" "$MAKI_SESSIONS" "$COPILOT_STORE" \
            "$COPILOT_STATE" "$PI_SESSIONS" "$PIG_SESSIONS" 2>/dev/null)
    else
        # No python: python-free status checks, no labels.
        while IFS=$'\t' read -r session win pane title cwd panepid cmd <&3 && IFS= read -r line <&4; do
            info=${line#*|}
            st=""
            [ -n "$info" ] && st=$(pane_status "$info" "$cwd" "$ps_snap")
            results="$results${st}${us}"$'\n'
        done 3<<<"$panes" 4<<<"$agents"
    fi
    while IFS=$'\t' read -r session win pane title cwd panepid cmd <&3 && IFS= read -r line <&4 && IFS="$us" read -r st lb <&5; do
        info=${line#*|}
        # Agent column shows every agent in the pane (pane_row -> agent_color
        # caps it to $AGENT_MAX_SHOWN + "(N more)"). info is name-pid pairs
        # ("<name1> <pid1> <name2> <pid2>..."); the names are the odd tokens.
        agents_disp=$(printf '%s' "$info" | awk '{for(i=1;i<=NF;i+=2) printf "%s%s", (i>1?" ":""), $i}')
        pane_row "$session" "$win" "$pane" "$title" "$cwd" "$cmd" "$agents_disp" "$st" "$lb"
    done 3<<<"$panes" 4<<<"$agents" 5<<<"$results" |
    # Order: active pane first (pin, field 1), then panes with a detected agent
    # (field 7, desc), then window index (field 3). sort -s keeps pane order for
    # ties, which the zero-padded filenames set.
    # Then one awk pass groups rows by window index (field 3) so each window's
    # panes stay together even though the sort can interleave windows. The
    # first-seen order of windows is preserved. For each group it emits the
    # window-name line, then its pane lines below with ├─/└─ tree connectors
    # (htop-style), padding the icon+dir and agent/cmd columns to a shared
    # width so the tab after each lands on the same terminal column.
    # Final layout: target \t win \t session \t pane_id \t display. fzf hides
    # fields 1-4 (--with-nth=5..); the focus bind reads 2-4 directly, and
    # --switch/--kill read fields 1-2. Window-name rows have an empty pane_id.
    # With AGENT_PICK_DIMS_FILE set, also writes "<widest display> <rows>" there
    # so the popup can be sized without measuring the rows again.
    sort -s -t"$tab" -k1,1r -k7,7r -k3,3n -k6,6 2>/dev/null | LC_ALL=C awk -F'\t' -v dims="${AGENT_PICK_DIMS_FILE:-}" -v dircols="$DIR_COLS" -v agentcols="$AGENT_COLS" '
        # Display width in characters: ANSI colors stripped. awk runs under
        # LC_ALL=C so every awk counts bytes and the [\200-\277] class matches
        # (macOS awk skips it in a UTF-8 locale); subtracting UTF-8
        # continuation bytes leaves one per character.
        function width(s,   t, n) {
            t = s
            gsub(/\033\[[0-9;]*m/, "", t)
            n = length(t)
            if (!utf) n -= gsub(/[\200-\277]/, "", t)
            return n
        }
        # Column 1 is icon (1) + 2 spaces + dir, so its floor is DIR_COLS + 3.
        BEGIN { utf = (length("\342\224\234") == 1); m1 = dircols + 3; m2 = agentcols }
        {
            # Group key is session+window, not window index alone: different
            # sessions can reuse the same index (three ssh sessions each with
            # a window 1 would otherwise collapse into one group).
            sess = $2; sub(/^pane:/, "", sess); sub(/:.*/, "", sess)
            w = $3
            gk = sess SUBSEP w
            if (!(gk in seen)) {
                seen[gk] = 1; order[++ng] = gk; nm[gk] = $4
                sn[gk] = sess; wn[gk] = w
                # Track sessions and their windows in first-seen order so the
                # END block can build a 3-level tree: session > window > pane.
                if (!(sess in sess_seen)) {
                    sess_seen[sess] = 1; sess_order[++ns] = sess; swcnt[sess] = 0
                }
                swcnt[sess]++
                sws[sess, swcnt[sess]] = gk
            }
            c = ++cnt[gk]
            # Show the agent name if one is running, else the pane command.
            proc = ($7 != "") ? $7 : $9
            ps = sess
            pid = $2; sub(/.*:/, "", pid)
            tgt[gk, c] = $2; psn[gk, c] = ps; pnid[gk, c] = pid
            col1[gk, c] = $6 "  " $5; col2[gk, c] = proc; ttl[gk, c] = $8
            if (width(col1[gk, c]) > m1) m1 = width(col1[gk, c])
            if (width(proc) > m2) m2 = width(proc)
        }
        END {
            # 3-level tree. The window line is indented 2 cols under the
            # session; the pane line is indented 6 cols under the window, with
            # a ├─/└─ connector so the icon column lines up across every pane
            # row. The connector is 4 display columns plus a space.
            for (si = 1; si <= ns; si++) {
                s = sess_order[si]
                lines[++nl] = "sess:" s "\t\t" s "\t\t" "\033[1m" s "\033[0m"
                nw = swcnt[s]
                for (wi = 1; wi <= nw; wi++) {
                    gk = sws[s, wi]; w = wn[gk]
                    wbr = (wi < nw) ? "  ├─ " : "  └─ "
                    lines[++nl] = "win:" sn[gk] ":" w "\t" w "\t" sn[gk] "\t\t" wbr nm[gk]
                    # Pane rows continue the vertical bar from the window
                    # connector down to the next window: if this window is not
                    # the last, col 3 holds a │ so the line stays connected;
                    # for the last window it is blank. The pane connector then
                    # sits at cols 7-9, keeping the icon column fixed.
                    rail = (wi < nw) ? "  │   " : "      "
                    for (j = 1; j <= cnt[gk]; j++) {
                        pbr = (j < cnt[gk]) ? "├─ " : "└─ "
                        a = rail pbr col1[gk, j]; b = col2[gk, j]
                        a = a sprintf("%" (m1 + 9 - width(a)) "s", "")
                        b = b sprintf("%" (m2 - width(b)) "s", "")
                        lines[++nl] = tgt[gk, j] "\t" w "\t" psn[gk, j] "\t" pnid[gk, j] "\t" a "\t" b "\t" ttl[gk, j]
                    }
                }
            }
            for (k = 1; k <= nl; k++) {
                print lines[k]
                d = lines[k]
                sub(/^[^\t]*\t[^\t]*\t[^\t]*\t[^\t]*\t/, "", d)
                if (width(d) > mw) mw = width(d)
            }
            if (dims != "") print mw, nl > dims
        }
    '
}

# Emit-only mode: used as fzf's input source and reload command.
if [ "${1:-}" = "--emit" ]; then
    emit_rows
    exit 0
fi

# Switch mode: given a full emit line, switch the client to that window.
# Field 1 (tab-delimited) is "pane:<session>:<pane_id>" for pane rows or
# "win:<session>:<index>" for window header rows; field 2 is the window index
# on both line types. Using "<session>:<window>" makes cross-session switching
# work (a bare window index can't resolve a window in another session).
# Briefly tint a pane's background, then reset it in the background. Same
# mechanism as the pane-focus-in hook in tmux.conf, but explicit so the picker
# flashes the target reliably (the hook fires hidden behind the popup, or on a
# window whose flash lands off-screen). $1 = pane id. The reset is a delayed
# background run-shell targeting the exact pane id, so rapid navigation can't
# leave a pane stuck tinted. Note: tmux pane bg only shows through cells the app
# leaves unpainted, so this reads strongest on shells/blank areas and is subtler
# over full-screen TUIs.
flash_pane() {
    local pane="$1" tint="${2:-colour237}"
    [ -n "$pane" ] || return
    tmux select-pane -t "$pane" -P "bg=$tint" 2>/dev/null
    tmux run-shell -b -d0.1 "tmux select-pane -t '$pane' -P 'bg=default'" 2>/dev/null
}

if [ "${1:-}" = "--switch" ] || [ "${1:-}" = "--focus" ]; then
    # --focus is the live navigation preview (fired on every row the cursor
    # lands on); --switch is the committed selection (Enter). They share the
    # switch logic below but differ on window-header rows: see the win: guard.
    preview=0; [ "${1:-}" = "--focus" ] && preview=1
    line="${2:-}"
    target=$(printf '%s' "$line" | cut -f1)
    case "$target" in
        win:*) sess=${target#win:}; sess=${sess%%:*} ;;  # drop the :<index> tail
        *)     sess=${target#pane:}; sess=${sess%%:*} ;;  # drop the :<pane_id> tail
    esac
    win=$(printf '%s' "$line" | cut -f2)
    [ -n "$win" ] && {
        # Pane rows: switch to the window AND select the exact pane. Window-name
        # rows only switch the window (no pane_id in the target).
        case "$target" in
            pane:*) paneid=${target##*:} ;;
            *)      paneid="" ;;
        esac
        tmux switch-client -t "${sess}:${win}" 2>/dev/null \
            || tmux select-window -t "$win" 2>/dev/null
        [ -n "$paneid" ] && tmux select-pane -t "$paneid" 2>/dev/null
        # Flash the pane we moved to, EXCEPT when live-previewing (--focus) a
        # window-header row. A header previews the same pane as the first child
        # row right below it, so flashing both would flash that pane twice as
        # the cursor passes the header then the child. On a header we still
        # switch (so hovering it isn't dead - it previews the window), just
        # without the flash; the child row does the flash. Pane rows always
        # flash, and Enter (--switch, preview=0) flashes headers too.
        if [ -n "$paneid" ] || [ "$preview" = 0 ]; then
            flash_pane "${paneid:-$(tmux display-message -p -t "${sess}:${win}" '#{pane_id}' 2>/dev/null)}"
        fi
    }
    exit 0
fi

# Kill mode: cursor on a pane row kills that pane; cursor on a window-name row
# kills the whole window. Both first kill the process subtree(s) so agents and
# long-lived children don't outlive the pane/window, then let tmux remove it.
# Pane targets are "pane:<sess>:<pane_id>", window targets are "win:<sess>:<index>".
# Run via fzf's execute() (not execute-silent) so we have a tty to prompt on.
if [ "${1:-}" = "--kill" ]; then
    line="${2:-}"
    target=$(printf '%s' "$line" | cut -f1)
    # The pane the popup was opened from: killing it (directly, or as part of
    # its window) would kill this session's own process tree. Refuse up front.
    # This is $home_pane (exported by the popup opener), NOT the live current
    # pane: live preview switches the client to the hovered row, so the live
    # current pane is the previewed target and would make every kill refuse.
    # Falls back to the live pane if home_pane is unset (direct invocation).
    cur_pane="${home_pane:-$(tmux display-message -p '#{pane_id}' 2>/dev/null)}"
    case "$target" in
        sess:*)
            # Session header: a visual group label, not killable here.
            printf 'not killable: session header\n' > /dev/tty
            ;;
        win:*)
            sess=${target#win:}; sess=${sess%%:*}
            win=${target##*:}
            # Refuse if the current pane is in this window.
            if [ -n "$cur_pane" ] && printf '%s\n' "$(tmux list-panes -t "${sess}:${win}" -F '#{pane_id}' 2>/dev/null)" | grep -qx "$cur_pane"; then
                printf 'refusing: that window holds the pane you are in\n' > /dev/tty
                exit 0
            fi
            printf 'Kill window %s:%s? [y/N] ' "$sess" "$win" > /dev/tty
            read -r ans < /dev/tty
            case "$ans" in
                [yY]*)
                    # Kill every pane's process tree in the window, then remove it.
                    for p in $(tmux list-panes -t "${sess}:${win}" -F '#{pane_id}' 2>/dev/null); do
                        kill_pane_tree "$p"
                    done
                    tmux kill-window -t "${sess}:${win}" 2>/dev/null
                    ;;
            esac
            ;;
        *)
            # pane:<sess>:<pane_id> - kill just this pane.
            rest=${target#pane:}
            paneid=${rest##*:}
            if [ -n "$cur_pane" ] && [ "$paneid" = "$cur_pane" ]; then
                printf 'refusing: that is the pane you are in\n' > /dev/tty
                exit 0
            fi
            printf 'Kill pane %s? [y/N] ' "$paneid" > /dev/tty
            read -r ans < /dev/tty
            case "$ans" in
                [yY]*)
                    kill_pane_tree "$paneid"
                    tmux kill-pane -t "$paneid" 2>/dev/null
                    ;;
            esac
            ;;
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
AGENT_PICK_HEADER="loading  •  claude ~/.claude  •  maki ~/.maki  •  copilot ~/.copilot"
# No python: labels are off and copilot/pig status degrades to unknown. Say so
# in the header so the empty label column isn't mistaken for a bug.
[ -n "$PYTHON_BIN" ] || AGENT_PICK_HEADER="$AGENT_PICK_HEADER  •  no python - labels off"
export AGENT_PICK_HEADER
legend="enter ⇄    esc ⊘    ^r ↻    ^k ⊗"
export legend
min_popup_width=80

# Live navigation preview, fired by fzf on every row the cursor lands on. One
# tmux call (fields: {2}=window index, {3}=session, {4}=pane id) instead of
# re-running this script: a bash start plus its cut/tmux calls cost ~170-210ms
# per arrow key, and execute-silent blocks fzf until it returns. Pane rows
# switch, select and briefly tint the pane; window-name rows (empty {4}) only
# switch, so passing a header doesn't flash the same pane twice.
# This is a tmux format string, not shell code: the \; are literal separators
# for tmux's command parser, so shellcheck's quote/backslash warnings are false.
# shellcheck disable=SC2089,SC2090
AGENT_PICK_FOCUS='if [ -n {4} ]; then tmux switch-client -t {3}:{2} \; select-pane -t {4} \; select-pane -t {4} -P bg=colour237 \; run-shell -b -d0.1 "tmux select-pane -t {4} -P bg=default"; elif [ -n {2} ]; then tmux switch-client -t {3}:{2}; fi'
# shellcheck disable=SC2090
export AGENT_PICK_FOCUS

# Size the popup to its content: render the rows once, measure the widest
# visible line (ANSI stripped, counted in display columns) and the row count,
# then derive width/height clamped to the client. fzf reads the same rows so
# what we measured is what's shown; ctrl-r reload still re-runs --emit live.
rows_file=$(mktemp "${TMPDIR:-/tmp}/tmux-agent-pick-rows.XXXXXX")
# emit_rows writes "<widest display line> <row count>" to the dims file while it
# renders, so the popup is sized from the same pass that built the rows.
AGENT_PICK_DIMS_FILE="$rows_file.dims" emit_rows > "$rows_file" 2>/dev/null

pop_w=""; pop_h=""
dims=""
read -r dims_w dims_h < "$rows_file.dims" 2>/dev/null && dims="$dims_w $dims_h"
rm -f "$rows_file.dims"
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
# The pane the popup is opened from. Live preview (AGENT_PICK_FOCUS) switches
# the client to whatever row the cursor is on, so the live "current pane" is
# NOT a reliable "where am I" by the time the user presses C-k. The kill guard
# must compare against this home pane (the one actually running the popup), not
# the previewed pane, or every kill of the previewed target gets refused.
home_pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null)
export home_pane

fzf_cmd="cat $rows_file | fzf \
  --ansi --no-sort --exact --cycle \
  --layout=reverse \
  --delimiter='\t' \
  --with-nth=5.. \
  --with-shell='/bin/sh -c' \
  --prompt=' search  ' \
  --header=\"\$AGENT_PICK_HEADER\" \
  --bind=ctrl-j:down \
  --bind='load:change-header:' \
  --bind=\"focus:execute-silent:\$AGENT_PICK_FOCUS\" \
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
        -e "AGENT_PICK_FOCUS=$AGENT_PICK_FOCUS" -e "home_pane=$home_pane" \
        -T "$ctitle" "$fzf_cmd"
else
    tmux display-popup -E -w "$eff_w" -h 33% \
        -e "AGENT_PICK_HEADER=$AGENT_PICK_HEADER" -e "legend=$legend" \
        -e "AGENT_PICK_FOCUS=$AGENT_PICK_FOCUS" -e "home_pane=$home_pane" \
        -T "$ctitle" "$fzf_cmd"
fi
rm -f "$rows_file"

# Landing flash. On the final selection the target pane was already focused
# (behind the popup) during navigation, so closing the popup fires no new
# focus-in. Flash the now-active pane explicitly here, after the popup is gone,
# so it's clear where we landed. Subtler tint than the navigation flash: you're
# already looking at the pane you picked, so this is a gentle confirmation.
flash_pane "$(tmux display-message -p '#{pane_id}' 2>/dev/null)" colour235