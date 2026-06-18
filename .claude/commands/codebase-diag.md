---
description: Run five git log commands to diagnose a new codebase before reading any source files
argument-hint: optional target directory (default: pwd)
allowed-tools: Bash(git:*), Bash(sort*), Bash(uniq*), Bash(head*), Bash(grep*)
---

# Codebase Diagnostics — /codebase-diag

_credit/source: [The Git Commands I Run Before Reading Any Code](https://piechowski.io/post/git-commands-before-reading-code/)_

Run five git log commands that diagnose a new codebase before opening any files. Reveals churn hotspots, bus factor, bug clusters, velocity trends, and firefighting frequency.

## Step 1: Resolve target directory

If the user provided an argument in `$ARGUMENTS`, use it as the target directory (must be inside the repo). Otherwise default to `$(pwd)`. Verify it exists and is within the git working tree before proceeding.

```bash
TARGET_DIR="${1:-$(pwd)}"
cd "$TARGET_DIR" && git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo"; exit 1; }
```

## Step 2: Run all five commands in sequence

Execute each command, capture output, and present it with the section header shown below. Do NOT skip any step.

### 2a. File churn hotspots

```bash
git log --format=format: --name-only --since="1 year ago" | sort | uniq -c | sort -nr | head -20
```

Run from `app/` or `src/` when possible (not repo root), so lockfiles/changelogs/generated code don't drown out real source. The top 20 most-changed files reveal where pain concentrates.

### 2b. Bus factor

```bash
git shortlog -sn --no-merges
```

Contributors ranked by commit count. One person at 60%+ with no recent commits = bus factor risk. Note: squash-merge workflows skew this (shows who merged, not who wrote).

### 2c. Bug clusters

```bash
git log -i -E --grep="fix|bug|broken" --name-only --format='' | sort | uniq -c | sort -nr | head -20
```

Bug-related commits by file. Cross-reference with the churn list (2a) — files appearing on both are highest risk: keep breaking, keep patched, never fixed.

### 2d. Velocity over time

```bash
git log --format='%ad' --date=format:'%Y-%m' | sort | uniq -c
```

Commit count per month across the repo's history. Sharp drops = someone left. Declining curve over 6-12 months = losing momentum. Spikes followed by quiet months = batched releases, not continuous shipping.

### 2e. Firefighting frequency

```bash
git log --oneline --since="1 year ago" | grep -iE 'revert|hotfix|emergency|rollb[ack]'
```

Emergency-style commits in the last year. High count = team tiptoeing around land mines rather than shipping with confidence.

## Step 3: Present findings

Display all five sections with clear headers. Highlight any files that appear on BOTH the churn list (2a) and bug list (2c) — these are the single biggest risk areas.

If bus factor (2b) shows one person at 60%+ of commits AND their last commit is older than 6 months, flag it explicitly as a crisis.

If velocity (2d) shows a sharp decline or near-zero activity in recent months, note it.

Keep the presentation concise — raw output + brief callouts, no fluff.
