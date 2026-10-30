---
name: draft-pr
description: Open a draft pull request for the current branch using the repo's PR template. Use when asked to open, create or draft a PR.
user-invocable: true
allowed-tools: Bash(git:*), Bash(gh pr:*), Bash(gh repo:*), Read, Write
---

# Draft PR

Opens a draft PR from the current branch. The body follows the repo's PR template and the rules below.

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

Find the template: `.github/PULL_REQUEST_TEMPLATE.md`, `.github/pull_request_template.md`, `docs/`, the repo root, or a `PULL_REQUEST_TEMPLATE/` directory (if several, ask which). Use its headings in its order. Delete a section only if it is empty.

If there is no template, use:

```
## Summary
## Changes
## Validation / Examples
```

With a template, Validation / Examples becomes an `### Examples` subsection at the end of Changes, so the example rules below apply there. A subsection of Changes is not an extra section.

Template-only sections: Ticket (the key from the branch name, or ask; "None filed." if none) and Documentation (paths of the docs updated).

## Rules

Check every rule against the body before showing it.

1. Never add sections beyond the template's or the fallback's. An `### Examples` subsection inside Changes is allowed.
2. Describe only the pushed diff; no local files, scripts or state.
3. Tone and length follow the system prompt's style rules and the
   `create` style pass: answer first, no recap, no emdashes, no emojis,
   fewest words.
4. No attribution line; no mention of the AI model or tool.
5. Link PRs as #NN. Ticket keys only in the body, never in code or docs.
6. The Summary section is built in this order, and nothing else:
   a. **Summary sentence.** Up to about 150 characters. Says only what
      the PR changes.
   b. **Key terms.** A list of 3-5 words the Changes lean on that a
      newcomer could misread ("field", "handler", "context"). One line
      each, defined with example code, not prose: what it is, shown in
      existing code (link on the default branch), and, where the stack's
      goal depends on it, why it matters (what goes wrong today without
      it). A term that only restates its name has failed. No length cap.
   c. **Relevance statement.** Only if the PR adds a component meant to
      be used by current code or a later PR in the stack. One sentence,
      as its own paragraph, that shows how existing code would use the
      component. It has: a link to the existing code that would change
      (`blob/<default>/...`, not a commit SHA; on the PR's branch if the
      code is not on the default branch yet), the one-line call, a short
      parenthetical on how that code works now (what runs through it,
      which components), and when the change lands: "(next PR, in #NN)",
      "(previous PR, in #NN)", "(later, in #NN)" or "(in this PR)". Check
      the claim against the code first. Aim for about 100 characters; go
      past that when the link, call and timing need it. If it is too
      long, shorten the summary sentence first, then trim words. Skip the
      statement only if it still says nothing a reader could not get from
      the summary.
   d. **Current behavior, before these changes.** What happens today, with
      a multi-line example. Never in Changes or Examples. No length cap.
   Count characters on rendered text: link text counts, the URL, the
   backticks and the bold markers do not.
7. Changes has one short bullet per change a reviewer cannot see from the
   diff, naming the function, flag, env var or file in backticks. Say why
   only where it is not obvious.
   Write each bullet for a reader with no editor or LSP: no unexplained
   terms ("later field", "the record's own"), no code-internal jargon. If a
   bullet describes a rule, precedence, ordering or edge case, show it in
   `### Examples` with a short code snippet and its real output. Point to
   it by bolded name, never by number: `see **"Replaced field"** example below`, so a reader
   can find it with a text search. With only a few examples, "example(s)
   below" is enough. Name each example with a bold label. A bullet that needs the diff open to
   understand has failed.
   Each bullet carries a relevance justifier: a few words or an
   example showing why the change matters to existing code, so the reader
   needs no editor to see it.
   Keep the bullet itself short: state what the thing is or does and let
   the example carry the detail (precedence, overwriting, ordering).
8. Changes skips renames, moves, file lists, comment updates and other
   follow-on edits. Group a move or refactor into one bullet.
9. Docs updated to match the code are one bullet: "Updated `<file>` to
   match." If the docs add something beyond the code change, state its
   effect in one short sentence.
10. Breaking changes go under Changes, with who is affected.
11. Validation / Examples is very concise: Before and After labels,
    always, unless the change adds output with no prior equivalent. Each
    has a multi-line fenced code block (command and output, or the value
    or config that changed). Multi-line wins over fewest words: expand
    compact JSON to indented form, one field per line, even when short.
    Show only what was actually run. For a new API, show the call (Go, shell,
    etc.) and its output, one example per rule a bullet states.
12. Never list what was not done, run or changed.
13. A checklist only if the template has one. Check a box only if true;
    otherwise leave it unchecked with a one-line reason.
14. Do not hard-wrap prose: one line per paragraph or bullet. Only code
    blocks keep their own line breaks.

## Example

A correctly formatted Before/After block:

````
Before:
```json
{
  "msg": "http request",
  "method": "POST",
  "status": 200
}
```

After:
```json
{
  "msg": "http request",
  "service.name": "orders.api",
  "method": "POST",
  "status": 200
}
```
````

## Before returning

- Every fenced block spans more than one line.
- Before and After are both present, or the change adds new output.
- No section outside the template or the fallback.
- No attribution, model or tool mention.
- No "not run", "not changed" or "not done" statements.
- No hard-wrapped prose lines.
