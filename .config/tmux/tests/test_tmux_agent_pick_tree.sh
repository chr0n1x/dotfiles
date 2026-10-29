#!/usr/bin/env bash
#
# Tests for the 3-level tree rendering in tmux-agent-pick.sh --emit
# (session > window > pane). The tree is built by an awk pass inside the
# script; this test drives that pass by faking the two tmux calls emit_rows
# makes (display-message for the current pane + width, and list-panes -a),
# then asserts on the emitted line structure.
#
# The agent-status resolution (claude/maki/codilot/...) lives in agent_pick
# and is tested separately in test_agent_pick.py. Here we feed panes with no
# detected agent (empty agent field) so the tree shape is what's under test,
# and we point PYTHON_BIN at nothing to skip the python label pass.
#
# Run with:  bash .config/tmux/tests/test_tmux_agent_pick_tree.sh

set -u

SCRIPT_DIR=$(cd -P "$(dirname "$0")" >/dev/null 2>&1 && pwd)
PICKER="$SCRIPT_DIR/../scripts/tmux-agent-pick.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/pick-tree-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# --- fake tmux on PATH -------------------------------------------------------
# emit_rows calls exactly two tmux subcommands:
#   tmux display-message -p '#{pane_id} #{window_width}'   -> "<pane> <width>"
#   tmux list-panes -a -F <fmt>                            -> tab-separated rows
# Both read their data from env vars so a test case can shape the tree.
cat > "$TMP/tmux" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
    display-message)
        # Only the no-target form is used by emit_rows; return the current
        # pane id + window width.
        printf '%s %s' "${FAKE_CUR_PANE:-%1}" "${FAKE_WIN_W:-200}"
        ;;
    list-panes)
        printf '%s' "$FAKE_PANES"
        ;;
    *)
        # Anything else (select-pane, run-shell, kill-*) is not exercised by
        # --emit; succeed quietly so a stray call can't fail the test.
        exit 0
        ;;
esac
FAKE
chmod +x "$TMP/tmux"

# --- run the picker's --emit with the fake tmux ------------------------------
# FAKE_PANES rows are tab-separated: session \t win \t pane_id \t window_name
# \t cwd \t pane_pid \t command. pane_pid points at a pid that has no agent
# child in the (empty) ps snap, so no agent is detected and the tree is pure.
emit() {
    PATH="$TMP:$PATH" FAKE_PANES="$1" FAKE_CUR_PANE="${2:-%1}" \
        PYTHON_BIN="" bash "$PICKER" --emit 2>/dev/null
}

# Strip the leading 4 tab-delimited fields (target, win, sess, pane_id) and
# any ANSI color codes, leaving just the visible tree text per line.
visible() {
    awk -F'\t' '{ print $5 }' | sed 's/\x1b\[[0-9;]*m//g'
}

# --- assertion helpers -------------------------------------------------------
PASS=0; FAIL=0
assert() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS+1))
        echo "ok   - $desc"
    else
        FAIL=$((FAIL+1))
        echo "FAIL - $desc"
        echo "  expected: $(printf '%s' "$expected" | sed 's/^/    /')"
        echo "  actual:   $(printf '%s' "$actual" | sed 's/^/    /')"
    fi
}
assert_grep() {
    local desc="$1" pattern="$2" haystack="$3"
    if printf '%s' "$haystack" | grep -qE "$pattern"; then
        PASS=$((PASS+1)); echo "ok   - $desc"
    else
        FAIL=$((FAIL+1))
        echo "FAIL - $desc (pattern '$pattern' not found)"
        printf '%s\n' "$haystack" | sed 's/^/    /'
    fi
}

# --- cases -------------------------------------------------------------------

# 1. One session, two windows, one pane each: session header first, then each
#    window indented under it with a connector, then each pane under its window.
panes1=$(printf '%s\n' \
    "s1	1	%1	nvim	/home/u	100	nvim" \
    "s1	2	%2	zsh	/home/u	200	zsh")
out1=$(emit "$panes1" | visible)
assert "single session header is the first line" "s1" "$(printf '%s\n' "$out1" | sed -n '1p')"
assert "one session + two windows + two panes -> 5 lines total" "5" "$(printf '%s\n' "$out1" | grep -c .)"
assert_grep "first window uses the ├─ (non-last) connector" "^  ├─ " "$out1"
assert_grep "last window uses the └─ (last) connector" "^  └─ " "$out1"
assert_grep "panes are indented under their window (6 cols + connector)" "^      [├└]─ " "$out1"

# 2. Two windows in ONE session both group under a single session header
#    (the original bug: two separate headers for two windows).
out2=$(emit "$panes1" | visible)
assert "exactly one session header line for one session" "1" "$(printf '%s\n' "$out2" | grep -c '^s1$')"

# 3. Two SESSIONS: each gets its own header, in first-seen order, with its
#    windows grouped under it.
panes3=$(printf '%s\n' \
    "sA	1	%1	nvim	/home/u	100	nvim" \
    "sA	2	%2	zsh	/home/u	200	zsh" \
    "sB	1	%3	emacs	/home/u	300	emacs")
out3=$(emit "$panes3" | visible)
assert "two sessions -> two session headers" "2" "$(printf '%s\n' "$out3" | grep -cE '^(sA|sB)$')"
# sA's header must come before sA's windows, which must come before sB's header.
first_sa=$(printf '%s\n' "$out3" | grep -n '^sA$' | cut -d: -f1)
first_sA_win=$(printf '%s\n' "$out3" | grep -nE '^  [├└]─' | head -1 | cut -d: -f1)
first_sb=$(printf '%s\n' "$out3" | grep -n '^sB$' | cut -d: -f1)
assert "sA header precedes sA's first window" "1" "$([ "$first_sa" -lt "$first_sA_win" ] && echo 1 || echo 0)"
assert "sA's window precedes sB header" "1" "$([ "$first_sA_win" -lt "$first_sb" ] && echo 1 || echo 0)"

# 3b. The pane under a NON-last window carries a │ at col 3 so the vertical
#     bar from the window connector stays connected down to the next window.
#     The pane under the LAST window has no │ (blank col 3).
panes3b=$(printf '%s\n' \
    "s1	1	%1	nvim	/home/u	100	nvim" \
    "s1	2	%2	zsh	/home/u	200	zsh")
out3b=$(emit "$panes3b" | visible)
# pane under window 1 (non-last): the prefix carries a │ so the vertical
# bar from the window connector stays connected down to the next window.
pane_nonlast=$(printf '%s\n' "$out3b" | sed -n '3p')
assert_grep "pane under a non-last window carries a │" "^  │" "$pane_nonlast"
# pane under window 2 (last): no │, just blank padding in the rail.
pane_last=$(printf '%s\n' "$out3b" | sed -n '5p')
assert "pane under the last window has no │" "0" "$(printf '%s' "$pane_last" | grep -o '│' | wc -l | tr -d ' ')"

# 4. A window with multiple panes: each pane gets a connector, last one └─.
panes4=$(printf '%s\n' \
    "s1	1	%1	nvim	/home/u	100	nvim" \
    "s1	1	%2	nvim	/home/u	110	nvim" \
    "s1	1	%3	zsh	/home/u	200	zsh")
out4=$(emit "$panes4" | visible)
# 1 session header + 1 window + 3 panes = 5 lines.
assert "one window with 3 panes -> 5 lines" "5" "$(printf '%s\n' "$out4" | grep -c .)"
panelines=$(printf '%s\n' "$out4" | grep -E '^      [├└]─')
assert "3 pane connector lines" "3" "$(printf '%s\n' "$panelines" | grep -c .)"
assert_grep "last pane uses the └─ connector" "└─" "$panelines"
assert "first pane uses ├─ (not last)" "1" "$(printf '%s\n' "$panelines" | sed -n '1p' | grep -c '├─')"

# ---------------------------------------------------------------------------
# Kill-guard tests.
#
# The live-preview (AGENT_PICK_FOCUS) switches the client to whatever row the
# cursor hovers, so by the time the user presses C-k the live "current pane" is
# the previewed target, not the pane the popup was opened from. The kill guard
# must compare against $home_pane (the popup's home pane), not the live pane,
# or every kill of the previewed target gets refused as "the pane you are in".
#
# We test the guard's decision via the exit code of a timed --kill run:
#   0   = the guard refused (printed to /dev/tty, exited before the read)
#   124 = the guard passed (printed the prompt to /dev/tty, then blocked on the
#         read from /dev/tty until the timeout). We never answer, so no actual
#         kill happens.
# ---------------------------------------------------------------------------
kill_guard_exit() {
    # $1 = home_pane value, $2 = the full emit line (pane target).
    # Returns the --kill exit code (0 refused, 124 proceeded).
    PATH="$TMP:$PATH" home_pane="$1" FAKE_PANES="" \
        timeout 2 bash "$PICKER" --kill "$2" </dev/null >/dev/null 2>&1
    return $?
}

# A pane line for pane %2 (the zsh pane), built the way emit_rows does.
# The % in the pane id would be a printf format specifier, so use a literal
# string (printf '%s') to keep it verbatim.
kill_line() {
    printf '%s' 'pane:s1:%2	2	s1	%2	      └─   zsh'
}

# 5. home_pane is the nvim pane (%1); target is the zsh pane (%2). The live
#    current pane is %2 (preview switched to it), but the guard must compare
#    against home_pane (%1), so it must PROCEED (exit 124), not refuse (exit 0).
kline=$(kill_line)
kill_guard_exit "%1" "$kline"; rc=$?
assert "killing the previewed pane is allowed (guard uses home_pane, not live pane)" "124" "$rc"

# 6. home_pane IS the target pane (%2). The guard must REFUSE (exit 0) -
#    killing the pane you are actually in would kill the popup's own tree.
kill_guard_exit "%2" "$kline"; rc=$?
assert "killing the pane you are actually in is refused" "0" "$rc"

# 7. home_pane unset (direct invocation fallback). The guard falls back to the
#    live current pane (FAKE_CUR_PANE=%1). Target %2 != %1, so PROCEED (124).
PATH="$TMP:$PATH" FAKE_CUR_PANE="%1" FAKE_PANES="" \
    timeout 2 bash "$PICKER" --kill "$kline" </dev/null >/dev/null 2>&1
rc=$?
assert "with home_pane unset, guard falls back to the live pane" "124" "$rc"

# --- summary -----------------------------------------------------------------
echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
