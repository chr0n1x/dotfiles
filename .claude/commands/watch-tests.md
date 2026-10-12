---
name: watch-tests
description: Run tests in a tmux split or popup, watch the log for failures, and fix them in a loop until all pass. Use when the user asks to run tests, watch tests, or fix failing tests.
user-invocable: true
argument-hint: "Optional test command (e.g. \"cargo test\", \"pytest\", \"go test ./...\")"
allowed-tools: Bash(tmux:*), Bash(bash:*), Bash(mkdir:*), Bash(git:*), Read, Edit, Glob, Grep, memory
---

# Watch Tests and Fix Until Green

Run the project's test suite in a tmux split or popup, watch the log for failures, fix them, and re-run until all pass.

## Step 1: Detect the test command

If the user provided a test command in the argument, use it. Otherwise, infer from the working directory:

- `Cargo.toml` → `cargo test`
- `go.mod` → `go test ./...`
- `pyproject.toml`, `setup.cfg`, `pytest.ini` → `pytest`
- `package.json` → read `scripts.test` (vitest, jest, mocha, etc.)

If the runner cannot be confidently determined, ask the user.

Store the detected command in the project memory for future sessions:

```
memory write "watch-tests-<repo>" tags=[watch-tests] content="<test command>"
```

## Step 2: Launch the test run

Use the `tmux-ctrl` skill's split-pane pattern (option 2). This gives the user a visible pane with the test output and gives the agent a deterministic log file to read.

```bash
CWD="$(pwd)"
NVIM_PID=$(echo "$NVIM" | grep -oP '\d+(?=\.)')
AGENT_PID="$$"
TASK="test"
LOG="$CWD/.agents/${NVIM_PID}-${AGENT_PID}-${TASK}.log"
mkdir -p "$CWD/.agents"

ORIG_PANE=$(tmux display-message -p '#{pane_id}')
NEW_PANE=$(tmux split-window -h -t "$(tmux display-message -p '#{session_name}:#{window_index}')" -P -F '#{pane_id}')
tmux select-pane -t "$NEW_PANE" -T "test-${NVIM_PID}-${AGENT_PID}"
W=$(tmux display-message -p '#{window_width}')
tmux resize-pane -t "$NEW_PANE" -x $((W * 20 / 100))
sleep 1
tmux select-pane -t "$ORIG_PANE"

tmux send-keys -t "$NEW_PANE" -l "bash -c '<TEST_COMMAND> 2>&1 | tee $LOG; ec=\${PIPESTATUS[0]}; echo; echo \"exit: \$ec\" >> $LOG'"
tmux send-keys -t "$NEW_PANE" Enter
```

Ask the user before the first `split-window` (per the tmux-ctrl confirmation rule). Subsequent re-runs in the same pane do not need re-confirmation.

## Step 3: Wait for the result

Poll the log file. Do not block-wait; check for the `exit:` line:

```bash
tail -5 "$LOG"
```

- If `exit: 0` is present: all tests passed.
- If `exit: <nonzero>` is present: tests failed. Proceed to Step 4.
- If neither is present: the test run is still going. Wait up to 10 seconds, then check again. Repeat.

If the user is iterating (editing code while tests run), the test runner (cargo, go test, pytest, vitest) will pick up the next run automatically if it is in watch mode. If not in watch mode, re-run the test command in the same pane (send-keys to `$NEW_PANE`).

## Step 4: Read the failure

Read the log file for the failure details:

```bash
grep -B5 -A20 'FAIL\|failed\|error\|Error\|panic\|Panic' "$LOG" | tail -60
```

Read the relevant source files to understand the failure before editing.

## Step 5: Fix the failure

Make the minimal edit needed. Do NOT:
- Rewrite passing tests
- Change test logic (notify the user)
- Touch files unrelated to the failure

## Step 6: Re-run

Re-run the test command in the same pane:

```bash
tmux send-keys -t "$NEW_PANE" -l "bash -c '<TEST_COMMAND> 2>&1 | tee $LOG; ec=\${PIPESTATUS[0]}; echo; echo \"exit: \$ec\" >> $LOG'"
tmux send-keys -t "$NEW_PANE" Enter
```

The log file is overwritten (tee truncates by default). Go back to Step 3.

## Step 7: Done

When all tests pass:

1. Report which files were changed and what was fixed.
2. Ask the user: "Close the test pane? (yes / no)"
   - Yes: `tmux kill-pane -t "$NEW_PANE"` (ask again per the tmux-ctrl kill confirmation rule)
   - No: leave it.
3. Ask the user: "Keep watching as you make more changes? (yes / no)"
   - Yes: stay in the loop (Step 3).
   - No: stop.
