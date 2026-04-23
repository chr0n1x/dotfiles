---
description: Poll a tmux pane for test results and fix failing tests in a loop until all pass
argument-hint: Optional tmux pane (e.g. 0:1.3)
allowed-tools: Bash(tmux capture-pane*), Bash(tmux list-panes*), Bash(bash:*), Read, Edit, Glob, Grep
---

# Watch Tests and Fix Until Green

## Runner summary grep patterns (lookup table)

| Runner | `SUMMARY_GREP` | `FAIL_GREP` | Done signal |
|--------|---------------|-------------|-------------|
| Jest / Vitest | `^(Test Suites\|Tests\|Time):` | `^(FAIL \|Test Suites\|Tests):` | `Test Suites:.*total$` |
| pytest | `^(PASSED\|FAILED\|ERROR\|=)` | `^(FAILED\|ERROR\|=)` | `=+.*passed` or `=+.*failed` |
| cargo test | `^test result:` | `^test result:` | `^test result:` |
| go test | `^(ok\|FAIL)\s` | `^FAIL\s` | `^(ok\|FAIL)\s` |

## Step 1: Detect test runner and framework

First, check graymatter memory for a previously stored runner for this project (if `memory_search` is available):

> `memory_search` agent_id=`watch-tests` query=`"test runner $(pwd)"`

If a stored result is found, use it and skip file detection. Set `RUNNER`, `SUMMARY_GREP`, `FAIL_GREP`, and `DONE_SIGNAL` from the lookup table above and jump to Step 2.

Otherwise, infer from the working directory. For example:

- `package.json` → read `scripts.test` and `devDependencies` to identify the runner (vitest, jest, mocha, etc.) and framework
- `pyproject.toml`, `setup.cfg`, `pytest.ini` → pytest
- `Cargo.toml` → cargo test
- `go.mod` → go test
- Scan for `*.test.*` or `*.spec.*` files to confirm

If the runner cannot be confidently determined, ask the user before continuing.

After detection, set `RUNNER`, `SUMMARY_GREP`, `FAIL_GREP`, and `DONE_SIGNAL` from the lookup table, then store for future sessions (if `memory_add` is available):

> `memory_add` agent_id=`watch-tests` text=`"$(pwd) runner=<RUNNER> summary_grep=<SUMMARY_GREP> fail_grep=<FAIL_GREP> done_signal=<DONE_SIGNAL>"`

## Step 2: Identify the tmux pane

If a pane was passed as `$ARGUMENTS`, use it. Otherwise, auto-detect:

```bash
tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index} [#{pane_current_command}] #{pane_title}"
```

Then peek at **each** `node`/`python`/`cargo`/`go` pane — do not just take `head -1`. Multiple same-type processes (e.g. a dev server and a test watcher) will both appear:

```bash
tmux capture-pane -t <PANE> -p -S -20 2>/dev/null | tail -10
```

Pick the pane whose output contains test runner output (pass/fail summaries, test names, "Watch Usage", etc.). Only ask the user if it genuinely cannot be determined.

## Step 3: Capture a pane sample

Confirm the runner and output format match expectations:

```bash
tmux capture-pane -t <PANE> -p -S -50 2>/dev/null
```

## Step 4: Poll for a new run (two phases)

Substitute `<PANE>` with the ID from Step 2 and `<DONE_SIGNAL>` with the pattern from the lookup table.

**Phase 1 — detect that a new run has started** (run in background):

```bash
bash -c 'prev_output=$(tmux capture-pane -t <PANE> -p -S -100 2>/dev/null); for i in $(seq 1 80); do sleep 3; output=$(tmux capture-pane -t <PANE> -p -S -100 2>/dev/null); if [ "$output" != "$prev_output" ]; then echo "RUN DETECTED"; exit 0; fi; done; echo "NO_CHANGE"'
```

Set `run_in_background: true`. When it completes: if `NO_CHANGE`, re-launch Phase 1. If `RUN DETECTED`, proceed to Phase 2.

**Phase 2 — wait for the run to finish and emit compressed output:**

Substitute `<DONE_SIGNAL>`, `<SUMMARY_GREP>`, and `<FAIL_GREP>` from the lookup table.

```bash
bash -c 'for i in $(seq 1 40); do sleep 2; output=$(tmux capture-pane -t <PANE> -p -J -S -200 2>/dev/null); last=$(echo "$output" | grep -E "<DONE_SIGNAL>" | tail -1); if [ -n "$last" ]; then if echo "$last" | grep -qi "fail\|error"; then echo "FAIL"; echo "$output" | grep -E "<FAIL_GREP>"; else echo "PASS"; echo "$output" | grep -E "<SUMMARY_GREP>"; fi; exit 0; fi; done; echo "STILL_RUNNING"'
```

Output is intentionally compressed: `PASS` + 3 summary lines, or `FAIL` + failing suite names only.

## Step 5: Check outcome

- `PASS` → report and stay in loop (go to Step 4)
- `FAIL` → proceed to Step 6
- `STILL_RUNNING` → re-run Phase 2

## Step 6: Capture and read failure details

```bash
tmux capture-pane -t <PANE> -p -S -300 2>/dev/null
```

Read the failure output. Before editing anything, read the relevant source file(s) to understand full context.

## Step 7: Fix the failure

Make the minimal edit needed. Do NOT:
- Rewrite passing tests
- Change test logic (notify user)
- Touch files unrelated to the failure

## Step 8: Loop

Go back to Step 4 and poll for the next run. Repeat until all tests pass.

## Step 9: Report

Tell the user which files were changed and what was fixed. Ask the user if they would like to keep polling as they are working. If yes, go to Step 4.
