---
name: pr-comment
description: Draft and post one short inline PR review comment in the
  user's style. Use when the user asks to comment on a PR, post a
  finding as a review comment, or turn a review finding into a
  question for the author. Verifies the claim, drafts, shortens with
  the user, then posts only after a yes.
user-invocable: true
---

# /pr-comment

One finding in, one short inline comment out. Nothing is posted until the
user says yes to the exact text.

## 1. Validate the claim

Before drafting, prove the finding is real with a cheap probe: run it, do
not just read the code. The PR branch may not be checked out and the
user's working tree may be dirty, so:

```bash
gh pr view <n> --json headRefOid,headRefName
git fetch upstream pull/<n>/head:refs/pr/<n>
git worktree add --detach <tmpdir>/pr<n>-<suffix> refs/pr/<n>
```

Add a throwaway test or script inside that worktree only, run it, then
`git worktree remove --force` it. Use a new directory name each time (a
removed worktree can leave a directory behind; leave it, do not delete
what you did not just create). Never touch the user's checkout.

If the probe cannot be run, say the claim is unverified and write the
comment as a question.

## 2. Pick the anchor

One comment, one line. Anchor on the changed line that causes the
problem, on the head commit. Confirm the line is in the PR diff (an
added line, side RIGHT). Print `path:line`.

## 3. Draft in the user's style

- A question, not a verdict: "can X do Y here?". Ask whether it can
  happen; do not assert the author is wrong.
- Name the symptom with a concrete example, not the mechanism. No
  jargon the reviewer may not know ("finish hook", library internals).
  No library names unless the reader needs them.
- If an example helps, use the shortest one that shows it (2 lines of
  code plus the observed result). Run it before showing it. If a
  trimmed version was never run, run it.
- No praise, no "not blocking" hedging unless asked, no recap, no
  emojis, no em dashes, no PR numbers or ticket IDs in prose.
- Lowercase and terse is fine. Aim for 1 to 3 lines.

Show the draft, the target (`PR`, `path:line`) and the exact text. Then
wait. When the user says "shorter", "simpler", "just the question",
rewrite and show again; do not post. Do not stack revisions into a
summary of what changed.

## 4. Post after an explicit yes

Only on a clear yes to the latest text. Post as a COMMENT review with
one inline comment and no body, via a JSON file in a temp dir:

```json
{
  "commit_id": "<headRefOid>",
  "event": "COMMENT",
  "comments": [
    {"path": "<path>", "line": <n>, "side": "RIGHT",
     "body": "<text>"}
  ]
}
```

```bash
gh api -X POST repos/<owner>/<repo>/pulls/<n>/reviews \
  --input <tmpdir>/review.json --jq '{id,state,html_url}'
```

Use `gh` for github.com. Use `APPROVE` or `REQUEST_CHANGES` only if the
user names it. Report the `html_url` and nothing else.

## Never

- Post without showing the exact text and getting a yes.
- Post more than the one comment the user approved.
- Edit the user's checkout, commit, or push.
