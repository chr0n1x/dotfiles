#!/usr/bin/env bash
#
# Tests for the multi-agent display in tmux-agent-pick.sh:
#   - pane_agents: collects every distinct agent in a pane's subtree (not just
#     the first), so a pane running two agents reports both.
#   - agent_color: caps the name list to AGENT_MAX_SHOWN shown names,
#     comma-separated, with a dim " (N more)" for the rest.
#
# The functions are internal to the picker script (no --flag exposes them), so
# this test extracts their definitions out of the script into a temp file and
# sources that - single source of truth, no duplicated logic.
#
# Run with:  bash .config/tmux/tests/test_tmux_agent_pick_agents.sh

set -u

SCRIPT_DIR=$(cd -P "$(dirname "$0")" >/dev/null 2>&1 && pwd)
PICKER="$SCRIPT_DIR/../scripts/tmux-agent-pick.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/pick-agents-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert() {
    local desc="$1" want="$2" got="$3"
    if [ "$want" = "$got" ]; then
        printf 'ok   - %s\n' "$desc"; PASS=$((PASS+1))
    else
        printf 'FAIL - %s\n  expected: %s\n  actual:   %s\n' "$desc" "$want" "$got"
        FAIL=$((FAIL+1))
    fi
}

# Extract a top-level function definition from the picker script. A function is
# `name() {` ... a line that is exactly `}`. This is good enough for the
# simple, brace-counted definitions in this script.
# Extract a top-level function: from the line `name() {` to the next line that
# is exactly `}`. The functions in this script are top-level and end with a
# bare `}` at column 0, so this is reliable for them.
extract_fn() {
    local name="$1"
    awk -v fn="$name" 'BEGIN{f=0} $0 == fn"() {" {f=1} f {print} f && /^\}$/ {exit}' "$PICKER"
}

# Source the functions we need into this test shell.
cat > "$TMP/fns.sh" <<EOF
$(extract_fn pane_agents)
$(extract_fn agent_color_one)
$(extract_fn agent_color)
EOF
# AGENT_NAMES + AGENT_MAX_SHOWN are set at the top of the picker; replicate the
# values the functions depend on (they read these globals). shellcheck can't see
# that the sourced functions consume them, so it flags them as unused here.
# shellcheck disable=SC2034
AGENT_NAMES="claude maki aider codex devin opencode copilot cline pi pig crush"
# shellcheck disable=SC2034
AGENT_MAX_SHOWN=2
# shellcheck disable=SC1091
source "$TMP/fns.sh"

# --- pane_agents: multi-agent collection -------------------------------------
# ps snapshot: root 100 (zsh) with maki (101) and pig (102) as children, plus an
# unrelated nvim (103). pane_agents should report BOTH maki and pig, primary pid
# = maki (101, higher priority).
snap='100 1 zsh
101 100 maki
102 100 pig
103 100 nvim'
out=$(printf '%s\n' "$snap" | pane_agents "100")
assert "pane_agents reports both agents as name-pid pairs" "100|maki 101 pig 102" "$out"

# Single agent: only claude in the subtree.
snap2='200 1 zsh
201 200 claude'
out2=$(printf '%s\n' "$snap2" | pane_agents "200")
assert "pane_agents single agent" "200|claude 201" "$out2"

# No agent: empty after the |.
snap3='300 1 zsh
301 300 nvim'
out3=$(printf '%s\n' "$snap3" | pane_agents "300")
assert "pane_agents no agent -> empty" "300|" "$out3"

# Priority order: pig (lower priority) present before maki in ps order, but the
# reported names must follow AGENT_NAMES order (maki before pig), and the
# primary pid is the highest-priority (maki).
snap4='400 1 zsh
401 400 pig
402 400 maki'
out4=$(printf '%s\n' "$snap4" | pane_agents "400")
assert "pane_agents orders pairs by priority (maki before pig)" "400|maki 402 pig 401" "$out4"

# --- agent_color: capping + formatting ---------------------------------------
# Two agents: both shown, comma-separated, no "more". Strip ANSI (each name is
# colored individually).
c1=$(agent_color "maki pi")
c1_plain=$(printf '%s' "$c1" | sed 's/\x1b\[[0-9;]*m//g')
assert "agent_color two agents -> comma list" "maki, pi" "$c1_plain"

# Three agents: first two shown, "(1 more)" for the third.
c2=$(agent_color "claude maki pig")
# Strip ANSI for the assertion (colors differ per name).
c2_plain=$(printf '%s' "$c2" | sed 's/\x1b\[[0-9;]*m//g')
assert "agent_color three agents -> 2 shown + (1 more)" "claude, maki (1 more)" "$c2_plain"

# Four agents: 2 shown + "(2 more)".
c3=$(agent_color "claude maki pi pig")
c3_plain=$(printf '%s' "$c3" | sed 's/\x1b\[[0-9;]*m//g')
assert "agent_color four agents -> 2 shown + (2 more)" "claude, maki (2 more)" "$c3_plain"

# Single agent: just the name (colored, but the text is the bare name).
c4=$(agent_color "crush")
c4_plain=$(printf '%s' "$c4" | sed 's/\x1b\[[0-9;]*m//g')
assert "agent_color single agent -> bare name" "crush" "$c4_plain"

# Each shown name carries its own color code (claude is rust 240;150;95).
assert "agent_color colors the first name" "1" \
    "$(printf '%s' "$c1" | grep -c $'\033\[38;2;110;185;240m')"

# --- summary -----------------------------------------------------------------
echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
