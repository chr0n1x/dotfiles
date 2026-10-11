---
name: draft-pr
description: Open a draft pull request for the current branch using the repo's PR template. Use when asked to open, create or draft a PR.
user-invocable: true
allowed-tools: Bash(git:*), Bash(gh pr:*), Bash(gh repo:*), Read, Write
---

# Draft PR

Opens a draft PR from the current branch. The body follows the repo's PR template and reads like the repo's recent merged PRs.

## Before opening

1. **Branch.** Run `git branch --show-current` and `git status --short`. Refuse to open from the default branch. If there are uncommitted changes, ask whether they belong in the PR; do not commit without being asked.
2. **Base.** Default branch: `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`. If the branch sits on another PR's branch (`git log --oneline <default>..HEAD` shows commits that belong to a parent PR), ask which base to use. If the branch is part of a stack, use `gh-stack` to push and create the PR; this skill then supplies only the title and body.
3. **Checks.** Run the checks the repo documents for the touched modules (look in `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `README`, `Makefile`, then CI config). If none are documented, say so and ask. Report only what was run.
4. **Docs.** If the change alters structure, commands or conventions, the relevant docs (`AGENTS.md`, `README`, feature docs) must be in the diff.

## Push

Pick the remote in this order: one the repo's `AGENTS.md` or `CLAUDE.md` names; the only remote if there is one; otherwise ask. Do not assume `origin`. Check with `git remote -v` and `gh repo set-default --view`; `origin` may be a personal fork.

```
git push -u <remote> <branch>
gh pr create --draft --base <base> --head <branch> --title "<title>" --body-file <file>
```

Write the body to a file in the scratchpad and pass `--body-file`. Confirm with the user before each push. Return the PR URL.

## Title

Use the repo's convention. Find it with `gh pr list --state merged --limit 5 --json title`. If there is none, use conventional-commit style: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`. This is broader on purpose than commit subjects, which are limited to `feat`/`fix`/`chore` (see the `commit-push` skill) - a PR may bundle a refactor or docs change its individual commits could not be named after. Lowercase, no period, under 70 characters, says what the PR does.

## Body

Find the template: `.github/PULL_REQUEST_TEMPLATE.md`, `.github/pull_request_template.md`, `docs/`, the repo root, or a `PULL_REQUEST_TEMPLATE/` directory (if several, ask which). Use its headings in its order. Delete a section only if it is empty. Read the last few merged PRs (`gh pr list --state merged --limit 3`, then `gh pr view <n>`) and match their tone and length.

If there is no template, use:

```
## Summary
One to three sentences: what the PR adds or changes and what it does, in plain words.

## Changes
- One bullet per change, naming the function, flag, env var or file in backticks.
- Say what the code does and why where it is not obvious, and link related PRs as #NN.

## Validation
The exact commands that were run, and in which modules.
```

Template sections that are not in the fallback:

- **Ticket (Jira or similar):** the key from the branch name, or ask. "None filed." if none.
- **Documentation:** paths of the docs updated.
- **Checklist:** copy the template's items verbatim.

Rules:

- Describe only what is in the pushed diff. Never mention uncommitted or untracked files, local scripts, or other local state; a reviewer cannot see them.
- Do not add a "Not in this PR" section.
- Check a checklist box only if it is true. Leave it unchecked, with a one-line reason, if not (for example no tests were added).
- Validation lists commands that were actually run. If something was not run, say so in one line.
- Ticket keys belong in the PR body only; never put them in code or docs.
- No emojis, no emdashes. End with the session's attribution line for PR descriptions, without an emoji.
- Note breaking changes under Changes, with who is affected.
