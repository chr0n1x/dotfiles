---
name: commit-push
description: Commit all changes and push to remote following repo conventions. Use when the user asks to commit, or asks how changes should be committed, split, or messaged.
user-invocable: true
argument-hint: "[optional commit message override]"
allowed-tools: Bash(git:*), Read, Write, Edit, Bash(echo*), Bash(grep*)
---

# Commit Push - /commit-push (alias: /cpoh)

Commit and push following repo-specific conventions.

## Step 1: Gather context

1. Read the project's `MEMORY.md` if it exists (check `project/memory/` and project root) for commit conventions, push rules, branch naming.
2. If no MEMORY.md, read `CLAUDE.md` for commit style hints.
3. If the branch has an open PR, run `gh pr view --json baseRefName,headRefName,headRefOid,url`. Check `git remote -v` and branch upstreams, but do not infer stack membership or the canonical push remote from upstream config alone.
4. Check that the extension is installed: `gh stack --help >/dev/null 2>&1`. If it fails, tell the user `gh stack` is not installed (`gh extension install github/gh-stack`), that stack membership could not be checked, and that the branch is being treated as non-stack only for that reason. Ask whether to continue or install first. Do not fall back silently.
5. If `gh stack` is installed and the PR or branch may be in a stack, use the `gh-stack` skill. Run `gh stack view --json`. "Not in a stack" or local-only tracking does not prove there is no remote stack; run `gh stack checkout <PR-number-or-URL>` to import the remote stack, then `gh stack view --json` again. Take the canonical remote from the PR and stack metadata.
6. If none of the above gives conventions, use the defaults in Step 4.

## Step 2: Gather changes

```bash
git status --short
git diff --stat
git diff
git log -5 --oneline
```

Identify staged, unstaged, and untracked files.

## Step 3: Stage files

Stage only relevant files, by path. Do NOT stage `.env`, credentials, lockfiles (unless the change is to the lockfile), or large binaries.

```bash
git add path/to/file1 path/to/file2
```

If `$ARGUMENTS` has a commit message, use it. Otherwise go to Step 4.

## Step 4: Craft commit message

**Subject (always):** `{type}: high-level summary`

- Type: `feat` | `fix` | `chore`
- Summary: a short phrase for what changed, not why or how
- Under 72 characters, imperative mood, no trailing period

**Body (optional):** Only when the subject alone is not enough for a future reader. Do NOT narrate decisions, rationale, or trade-offs (e.g. "we chose emptyDir over PVC because..."). If the subject tells the whole story, use subject only.

**Attribution (always in body):**
- Add `AI Model: <model-name>` as a standalone line, using the model actually running this session (from agent/session metadata or the system-provided model name, not environment variables). Keep the provider prefix if present. For local GGUF names, lowercase and drop `unsloth/`, `MTP`, `GGUF`, `UD-`. Examples: `unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-Q6_K` -> `qwen3.6-35b:Q6_K`; `claude-opus-4-8` -> `opus-4.8`.
- Last line, after a blank line: `Co-Authored-By: RannetAI <noreply@rannet.duckdns.org>`

**Split unrelated changes into separate commits.**

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

## Step 5: Commit

Write the message to a temp file and use `git commit -F`. Do NOT use `git commit -m "$(cat <<EOF ...)"`: the `"$(...)"` wrapper re-parses the body in the shell, so an apostrophe or backtick in the prose fails with `unexpected EOF`.

```bash
MSG_FILE="$(mktemp)"
cat > "$MSG_FILE" <<EOF
<subject line>
<body only if non-obvious, otherwise omit this line>

AI Model: <actual-session-model>

Co-Authored-By: RannetAI <noreply@rannet.duckdns.org>
EOF
git commit -F "$MSG_FILE"
rm -f "$MSG_FILE"
```

`<<EOF` is safe here because `cat` only writes the body to a file. If the body must contain a literal `$`, `` ` ``, or `\`, use `<<'EOF'` and fill in the model name afterward.

If the user gave an override message, use it verbatim without adding Co-Authored-By.

## Step 6: Stack-aware commit and push

Before committing or pushing, determine whether the branch is in a tracked or remote GitHub stack (see Step 1). If `gh stack` is not installed, the user must already have been told; run no `gh stack` commands, and do not push a branch that may be in a stack until the user confirms. Follow the `gh-stack` skill's confirmation gates and branch-chain procedures:

- Commit only the intended changes, on the branch that owns them. Do not switch stack branches with uncommitted changes unless they are verifiably preserved.
- A commit on a parent branch can require rebasing descendants. After committing, check `gh stack view --json` for `needsRebase`. Do not push descendants or adjust PR bases ad hoc.
- Take the canonical remote from the stack's branches/PRs and `gh stack view --json`, not from `origin` by default. `origin` may be a fork while another remote owns the stack PRs.
- Get explicit confirmation for each stack mutation (push, submit), naming the exact remote. Sync with `gh stack submit --auto --remote REMOTE`, then verify remote branch SHAs, PR heads/bases, and stack state.
- If the user explicitly asks to push a single stack branch, confirm the branch and canonical remote, then follow `gh-stack` guidance for descendants and sync.

For non-stack branches, use the push flow below.

## Step 7: Push (HARD GATE)

**NEVER run `git push` before the user has seen the full commit message AND explicitly confirmed.** A prior "yes" does not carry over to a later commit; each push needs its own confirmation.

In order:
1. Show the full commit message verbatim (subject, body, trailers), surrounded by decorators so it stands out.
2. Ask a direct yes/no question: "Push `<sha> <subject>` to `<remote>`?" Use the interactive question tool if available.
3. Wait for an explicit yes. Silence, a tangent, or an "ok" to a different question means do NOT push. If ambiguous, ask again.
4. Only then push:

- Stack branch: follow Step 6 and push to the canonical stack remote, not the configured `origin` upstream. `git push` alone does not update stacked PR bases.
- Non-stack branch: `git push`, or if no upstream is set, `git push -u origin $(git branch --show-current)`.

## Step 8: Report

- What was committed (files changed, commit SHA, subject)
- That the push succeeded
- The remote URL of the commit, if applicable

On failure (hook failure, push rejected, etc.), report the error and suggest a fix. Do NOT retry with `--force` or `--no-verify` unless explicitly asked.

## PR description style (when a PR is requested)

Preserve the repo's PR template and conventions. Match neighboring PRs' terse tone: a one- or two-sentence summary and short change bullets, with no marketing language or filler. State what changed and what is out of scope, without overclaiming. If the template asks for checks, give exact commands with passed/failed/not-run, and check only items actually satisfied. List only relevant documentation. Keep the title brief and in commit style.


## PR description (when a PR is requested)

Use the `draft-pr` skill. It owns the title and body rules.
