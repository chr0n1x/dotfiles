---
description: Poll tmux panes for test results and fix failing tests in a loop until all pass
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
| go test | `^(ok\|FAIL)\s` | `^FAIL\s` | `make\[1\]: Leaving directory` |

## Step 1: Detect test runner and framework

### 1a. Check project MEMORY.md first

Look for a file named `MEMORY.md` in the project root. If it contains test runner patterns (look for "watch-tests-patterns", "Runner:", "go test", etc.), use those directly — they override the generic lookup table below. Set `RUNNER`, `SUMMARY_GREP`, `FAIL_GREP`, and `DONE_SIGNAL` from the file and skip to Step 2.

### 1b. Check graymatter memory

If no MEMORY.md, check graymatter memory for a previously stored runner:

> `memory_search` agent_id=`watch-tests` query=`"test runner $(pwd)"`

If found, use it and skip to Step 2.

### 1c. Infer from project files

If neither 1a nor 1b yields results, infer from the working directory:

- `package.json` → read `scripts.test` and `devDependencies` (vitest, jest, mocha, etc.)
- `pyproject.toml`, `setup.cfg`, `pytest.ini` → pytest
- `Cargo.toml` → cargo test
- `go.mod` → go test
- Scan for `*.test.*` or `*.spec.*` files to confirm

If the runner cannot be confidently determined, ask the user before continuing.

After detection, store for future sessions (if `memory_add` is available):

> `memory_add` agent_id=`watch-tests` text=`"$(pwd) runner=<RUNNER> summary_grep=<SUMMARY_GREP> fail_grep=<FAIL_GREP> done_signal=<DONE_SIGNAL>"`

Also write patterns to the project's `MEMORY.md` if one doesn't exist yet (create it).

## Step 2: Poll all panes for test output

**No pane identification needed.** Instead of trying to find the right pane first, poll ALL tmux panes on every cycle and scan their combined output. This avoids the pain of identifying which pane holds the watcher.

```bash
# Capture tail -n 10 from every pane, concatenate with pane IDs as headers
tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index}" | while read pane; do
  echo "=== PANE: $pane ==="
  tmux capture-pane -t "$pane" -p -S -10 2>/dev/null
done
```

Store the combined output as `prev_output`. On each cycle, re-run the same command and compare. If output changed, parse it for test results.

## Step 3: Poll for a new run (single loop)

Run in background with `run_in_background: true`. Each iteration:

1. Capture all panes (tail -n 10 from each)
2. Compare against previous combined output
3. If unchanged, sleep 3s and repeat (up to 80 iterations = ~4 min)
4. If changed, parse for test results using the patterns from Step 1

**Parsing logic:**

```bash
combined=$(tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index}" | while read pane; do
  echo "=== PANE: $pane ==="
  tmux capture-pane -t "$pane" -p -S -200 2>/dev/null
done)

# Check for failure first
if echo "$combined" | grep -qE "<FAIL_GREP>"; then
  echo "FAIL"
  echo "$combined" | grep -E "<FAIL_GREP>"
elif echo "$combined" | grep -qE "<DONE_SIGNAL>"; then
  echo "PASS"
  echo "$combined" | grep -E "<SUMMARY_GREP>"
else
  echo "NO_RESULTS_YET"
fi
```

**Fallback if tmux capture is unreliable** (e.g. entr subprocesses running outside tmux): If polling detects changes but no DONE signal appears within timeout, fall back to running tests directly:
```bash
cd <project-dir> && go test ./...  # or equivalent for the runner
```

## Step 4: Check outcome

- `PASS` → report and stay in loop (go to Step 3)
- `FAIL` → proceed to Step 5
- `NO_RESULTS_YET` → sleep and continue polling
- Fallback direct test run: if it fails, proceed to Step 5; if it passes, report PASS

## Step 5: Capture and read failure details

```bash
tmux capture-pane -t <PANE> -p -S -300 2>/dev/null
```

Read the failure output. Before editing anything, read the relevant source file(s) to understand full context.

## Step 6: Fix the failure

Make the minimal edit needed. Do NOT:
- Rewrite passing tests
- Change test logic (notify user)
- Touch files unrelated to the failure

## Step 7: Loop

Go back to Step 3 and poll for the next run. Repeat until all tests pass.

## Step 8: Report

Tell the user which files were changed and what was fixed. Ask the user if they would like to keep polling as they are working. If yes, go to Step 3.
