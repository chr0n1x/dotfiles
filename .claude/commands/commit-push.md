---
name: commit-push
description: Commit all changes and push to remote following repo conventions
user-invocable: true
argument-hint: "[optional commit message override]"
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

**Subject line format (always):** `{type}: high-level summary`

- Type: `feat` | `fix` | `chore` (pick the most appropriate)
- Summary: a short phrase describing what changed, not why or how
- Keep under 72 characters, imperative mood, no trailing period

**Body (optional):** Only add a body when the change is non-obvious from the subject alone and a future reader would genuinely need the extra context. Do NOT narrate decisions, rationale, or trade-offs (e.g. "we chose emptyDir over PVC because..." is a no). If the subject tells the whole story, use a subject-only commit.

**Attribution (always in body):**
- Read `$CLAUDE_MODEL`, shorten it (lowercase, drop MTP/GGUF/UD), add `AI Model: <shortened>` as a standalone line. Examples: `unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-Q6_K` → `qwen3.6-35b:Q6_K`; `claude-opus-4-8` → `opus-4.8`.
- Add `Co-Authored-By: RannetAI <noreply@rannet.duckdns.org>` as the last line, blank line before it.

**If multiple unrelated changes exist, split into separate commits with clear messages for each.**

**Examples:**
```
fix: pin kreaps pods to arm64 nodes
```

```
feat: add PATH to wrapper and systemd unit
```

```
chore: bump app-template to 5.2.1

Wraps the new defaultPodOptions.nodeSelector support.
```

## Step 5: Detect model and commit

Shorten the model name from `$CLAUDE_MODEL` using these rules: lowercase, drop `unsloth/`, `MTP`, `GGUF`, `UD-` prefixes. Then execute:

```bash
SHORT_MODEL="${CLAUDE_MODEL:-claude-code}"
if [ "$SHORT_MODEL" != "claude-code" ]; then
  SHORT_MODEL="${SHORT_MODEL//-MTP/}"
  SHORT_MODEL="${SHORT_MODEL//-GGUF/}"
  SHORT_MODEL="${SHORT_MODEL//UD-/}"
fi
git commit -m "$(cat <<EOF
<subject line>
<body only if non-obvious, otherwise omit this line>

AI Model: $SHORT_MODEL

Co-Authored-By: RannetAI <noreply@rannet.duckdns.org>
EOF
)"
```

If the user provided an override message, use it verbatim without adding Co-Authored-By.

## Step 6: Push

**IMPORTANT**:
- ask for user to confirm whether it's ok or not to push FIRST.
- When asking - SHOW the user the full commit message (verbatim - subject, body and everything else) so they can evaluate what you just did.
- surround the commit message that you're showing them with some decorators so it's easy to distinguish the message vs surrounding interactions.

If they clearly say it's ok to push - push to the current branch's upstream:

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
