---
description: Commit all changes and push to remote following repo conventions
argument-hint: [optional commit message override]
allowed-tools: Bash(git:*), Read, Write, Edit, Bash(echo*), Bash(grep*)
---

# Commit Push — /commit-push (alias: /cpoh)

Automate the full commit-and-push workflow. Follow repo-specific conventions by reading project MEMORY.md or CLAUDE.md for commit style rules.

## Step 1: Gather context

1. Read the project's `MEMORY.md` if it exists (check `project/memory/` and project root). Look for sections about commit conventions, push rules, branch naming, etc.
2. If no MEMORY.md, read `CLAUDE.md` for any commit style hints.
3. If neither has conventions, use the defaults described in Step 4.

## Step 2: Gather changes

Run these commands to understand what will be committed:

```bash
git status --short
git diff --stat
git diff
git log -5 --oneline
```

Read all output. Identify which files are changed (staged + unstaged) and new/untracked files.

## Step 3: Stage files

Stage only relevant files — do NOT stage `.env`, credentials, lockfiles (unless the change is to the lockfile), or large binaries. Use specific file paths:

```bash
git add path/to/file1 path/to/file2
```

If the user provided an override commit message in `$ARGUMENTS`, use it. Otherwise proceed to Step 4.

## Step 4: Craft commit message

Write a concise, accurate commit message following these rules (override with conventions from Step 1):

**Format:** `type: brief description`

Types (pick the most appropriate):
- `feat` — new functionality or feature
- `fix` — bug fix
- `docs` — documentation changes
- `chore` — config, deps, tooling changes

**Rules:**
- Keep subject line under 72 characters
- Focus on the *why*, not the *what*
- Use imperative mood ("add" not "added")
- No trailing period
- If multiple unrelated changes exist, split into separate commits with clear messages for each
- Add `Co-Authored-By: claude-code <noreply@rannet.duckdns.org>` in the commit body

**Example:**
```
feat: add PATH to wrapper and systemd unit for go/make/git access
```

## Step 5: Commit

Execute:

```bash
git commit -m "$(cat <<'EOF'
<subject line>

<body if needed>

Co-Authored-By: claude-code <noreply@rannet.duckdns.org>
EOF
)"
```

If the user provided an override message, use it verbatim without adding Co-Authored-By.

## Step 6: Push

Push to the current branch's upstream:

```bash
git push
```

If there is no upstream set yet:

```bash
git push -u origin $(git branch --show-current)
```

## Step 7: Report

Tell the user:
- What was committed (files changed, commit SHA, subject line)
- That it was pushed successfully
- The remote URL of the commit if applicable

If anything failed (hook failure, push rejected, etc.), report the error and suggest a fix. Do NOT retry with `--force` or `--no-verify` unless explicitly asked.
