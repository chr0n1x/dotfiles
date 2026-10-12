---
name: create
description: Checkpoints for writing code, docs, PR text and reports. Use before adding a type, function, flag or config, and before saying a change is fixed or done, or when stating facts about code, infra or AWS.
user-invocable: true
---

# Create - /create (aliases: /code, /write, /style)

Two checkpoints. Each step is mechanical: do it, then continue.

## Before building

1. **Shape first.** For a new type, API or doc layout others will build on, show the shape before writing it: a realistic example value, nesting depth, and which PR in the stack it belongs to. Wait for approval.
2. **Search before adding.** Grep for an existing function, flag or config that does the job. Name it as file:line, or say none found.
3. **Omit first.** Can it be left out, or covered by an existing flag or value? Add a config value only if both answers are no.
4. **Say why.** Each new function, flag or file gets one line on why it exists. Comment anything non-obvious (e.g. it builds a response object as well as writing a record).
5. **Scope.** Name the PR or branch the change belongs to. Anything outside it goes in a parked list (a scratchpad file). If it belongs to another branch in a stack, name that branch and use `gh-stack`. Do not switch branches with uncommitted changes.

## Before saying done

1. **Run what the user looks at.** Run the exact test command, endpoint or page and report what you observed. Never report a fix from reading code alone. If it can't be run, say so.
2. **Ground claims.** Every factual claim gets a source: file:line, a command and its output, or a link. Otherwise label it recalled or unknown. Run `<tool> --help` before claiming a tool can do something.
3. **Four-point check** on any test or e2e result:
   - the result matches what the test claims to do
   - the test makes sense
   - the behavior matches the code, and the code makes sense
   - the output gives a consumer (UI, caller) enough to act on
4. **Keep what was learned.** If an investigation found something, write it into the nearest AGENTS.md. Could an agent starting cold skip this search? If not, the note is not done.
5. **Style pass** on all outgoing text: answer first, no recap, no offers, no emdashes, no emojis, fewest words that keep the facts. Reply: 3 sentences. PR description: use `draft-pr`.
6. **Leftovers.** List files created this session; the user decides keep or delete. Then offer `commit-push`. Never commit or push from /create.

## Hand-offs

Invoke the skill and follow it; do not do these inside /create.

- Commit or push: `commit-push` (aliases /commit, /push). Owns commit messages, stack checks and push confirmation.
- Open a PR: `draft-pr`. Owns the body template, base branch and push remote.
- Stacked branches or PRs: `gh-stack`. Owns every stack mutation and its confirmation.

## When blocked

If a read, auth or fetch fails, state what failed and what the user must change. Stop. Do not work around it or guess.

## Never print secrets

Do not cat `.envrc`, `.env` or credential files. Grep for the one name needed.

## Not owned by this session

Do not delete, switch or rewrite worktrees, branches or directories this session did not create; another agent may be using them. Ask first.
