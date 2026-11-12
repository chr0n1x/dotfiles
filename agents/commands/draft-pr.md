---
name: draft-pr
description: Open a draft pull request for the current branch using the repo's PR template, or rewrite an existing PR's description. Use when asked to open, create or draft a PR, or to update, fix or rewrite a PR description.
user-invocable: true
allowed-tools: Bash(git:*), Bash(gh pr:*), Bash(gh repo:*), Read, Write
---

# Draft PR

Opens a draft PR from the current branch, or rewrites an existing PR's description. The body follows the repo's PR template and the rules below.

## Before opening

1. **Branch.** Run `git branch --show-current` and `git status --short`. Refuse to open from the default branch. Ask whether uncommitted changes belong in the PR; never commit unasked.
2. **Base.** Default branch: `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`. If `git log --oneline <default>..HEAD` shows a parent PR's commits, ask which base to use. In a stack, push and create with `gh-stack`; this skill then supplies only the title and body.
3. **Checks.** Run the checks the repo documents (`AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `README`, `Makefile`, then CI config). If none are documented, say so and ask. Report only what was run.
4. **Docs.** If the change alters structure, commands or conventions, the docs that describe them are in the diff.

## Push

Use the remote the repo's `AGENTS.md` or `CLAUDE.md` names, else the only remote, else ask. Never assume `origin`; it may be a fork (`git remote -v`, `gh repo set-default --view`). Confirm with the user before each push.

```
git push -u <remote> <branch>
gh pr create --draft --base <base> --head <branch> --title "<title>" --body-file <scratchpad file>
```

Return the PR URL.

## Editing an existing PR

1. Save the live body with `gh pr view <n> --json body -q .body > <scratchpad>/pr-<n>.md` and edit that file.
2. Show the user only the changed parts, as a reader will see them, and wait for a yes.
3. Post with `gh pr edit <n> --body-file <file>`, read it back with `gh pr view`, and diff it against the file.
4. In a stack, grep the other PRs' bodies for the text you changed and fix them the same way.

## Title

The repo's convention (`gh pr list --state merged --limit 5 --json title`), else conventional-commit style: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:` (broader than commit subjects, since a PR may bundle a refactor or docs change). Lowercase, no period, under 70 characters, says what the PR does.

## Body

Use the repo's template (`.github/PULL_REQUEST_TEMPLATE.md`, `.github/pull_request_template.md`, `docs/`, the repo root or `PULL_REQUEST_TEMPLATE/`; ask if several): its headings in order, deleting a section only if it is empty. Without a template, use `## Summary`, `## Changes`, `## Validation / Examples`, with examples in `## Validation / Examples` after the checks. With one, examples go in an `### Examples` subsection at the end of Changes. Each check is listed with its command and result (`go test ./worker/...` passes). Add no other sections except the threshold chart section and `## Ticket` described below.

- **Ticket:** a final `## Ticket` section with only the linked key, taken from the branch name, or ask. If there is none, offer to create one with any ticketing skill if available (e.g. `jira`) before opening, and write "None filed." if the user declines.
- **Documentation:** paths of the docs updated.
- **Checklist:** only if the template has one. Check a box only if true; otherwise leave it unchecked with a one-line reason.

### Writing rules

- Every claim about the system comes from the diff, the code or facts the user gave; cut anything else. Describe only the pushed diff, never local files or state.
- Follow the `create` style pass: answer first, no recap, no emdashes, no emojis, fewest words. One line per paragraph or bullet; only code blocks keep line breaks.
- Write "on `main`", never with a date. Date only events (an incident range, a log line). Never "today", "now" or "currently".
- Link PRs as #NN; ticket keys only in the body. Read `blob/<default>` line numbers from the base repo, not `origin`: `git fetch <remote> <default>`, then `git show <remote>/<default>:<path>`. Link code that is not on the default branch yet on the PR's branch.
- No attribution, no mention of the AI model or tool, and no sentence about what was not done, run, changed or shown.
- Say each fact once. The failure is described only in the Summary's Problem.
- Every Mermaid `xychart-beta` names each `line`/`bar` series (GitHub draws the names as the legend) and sets fixed colors with `plotColorPalette`:

  ````
  ```mermaid
  ---
  config:
    themeVariables:
      xyChart:
        plotColorPalette: "#1f77b4, #ff7f0e"
  ---
  xychart-beta
      line "After" [5.0, 2.2, 1.1]
      line "Before" [5.0, 0.8, 0.5]
  ```
  ````
- Draw with Mermaid, not ASCII art: a flow, loop or call order the PR changes gets a `flowchart` or `sequenceDiagram` (before and after) in Examples; a metric over time or a value that changes with an input gets an `xychart-beta`. Keep text trees with `<-` markers for data shapes.
- Chart values come from real data (metrics, logs, a run) or the diff's formula, never invented. Scrub them first: no user or actor IDs, emails, account IDs, ARNs, hostnames or prod content; aggregate counts and rates are fine.

### Summary

These four parts, in this order, and nothing else.

**1. Problem**, for a reader who has never opened the repo. Fill in:

````
<What goes wrong today, in plain words. Name only the data file the problem is about: no source files, classes or methods.>

```
<picture of the data shape (folder, payload, table), with at least two `<-` markers: one on what the code uses today, one on what it misses or gets wrong>
```

<What happens next, in plain words.> <Only if the facts give a number: "In Prod, this behavior was observed in N <things> between <date> and <date>."> This PR <what it adds or changes, naming the main function or flag once>. <If this PR alone does not change the behavior, which PR does.>
````

Leave out the picture only if the problem has no data shape. If the text names several affected code paths, say which PR changes each one.

Example (another repo, to show the form only):

````
When two tenants request the same report on the same day, the second tenant gets the first tenant's cached copy. The cache after both requests:

```
report-cache/
├── 2026-03-02/sales.pdf    <- written for tenant A, then read by tenant B
└── (no entry for B)        <- what tenant B should have read
```

Tenant B sees another tenant's numbers until the entry expires 24 hours later. In Prod, this behavior was observed in 12 reports between 2026-02-20 and 2026-03-02. This PR adds the tenant id to the cache key in `ReportCache.keyFor`.
````

Check: the first sentence names no code; the picture has two `<-` markers; the PR's own function or flag appears only in the last sentences.

**2. Key terms**, under the standalone bold label `**Key terms to keep in context while reading this PR**` (not a heading). 2-4 lines: the Problem's terms in the order they appear there, then at least one for the mechanism this PR adds or changes. Each line:

```
- **<name a person would say>** ([`<CodeName>`](<link>)): <what it is, plain words>. <why the reader needs it to follow this PR>.
```

Example (same other repo; "Cache key" is the mechanism the PR changes):

```
- **Report cache** ([`ReportCache`](https://github.com/example/reports/blob/main/src/ReportCache.java#L20)): keeps each generated report for 24 hours so a repeat request skips generation. Only how entries are named changes here, not how long they are kept.
- **Cache key** ([`ReportCache.keyFor`](https://github.com/example/reports/blob/main/src/ReportCache.java#L41)): the path an entry is stored under, e.g. `2026-03-02/sales.pdf`. This PR changes what goes into this path.
```

If no class or field is the thing itself (a folder, a request), link the first code that receives it and say so: `([passed to `getDirectory`](<link>))`.

Check each line: the bold name is an ordinary phrase, not a file, class or method name; the link opens on the line that defines `<CodeName>` with `#L<n>` (read that line; if the line is unknown, look it up or ask, never link a bare file), and no two terms share a link; each claim in `<what it is>` has a code line or fact behind it; the last sentence does not restate the failure.

**3. Relevance statement**, only if the PR adds code that nothing calls yet, which existing code or another PR will call. Skip it when this PR's own diff is the caller. One sentence, as its own paragraph: a link to the code that would change, the one-line call, a short parenthetical on how that code works now, and when it lands: "(next PR, in #NN)", "(previous PR, in #NN)", "(later, in #NN)" or "(in this PR)". Check it against the code.

**4. Current behavior, before these changes.** Real captured output that shows the Problem (a log, a response, or a command and its output), after one line saying where it came from, e.g. "Stage worker log, one event appended to the folder above". Never constructed values.

### Changes

- One bullet per change a reviewer cannot see from the diff, naming the function, flag, env var or file in backticks. At most 2 sentences: what the change is, and where. Nothing the Summary already said, no mechanics the diff shows.
- Skip renames, moves, file lists and comment updates; group a refactor into one bullet. Docs updated to match are one bullet, "Updated `<file>` to match.", plus one sentence on anything they add.
- Breaking changes say who is affected.
- A rule, precedence, ordering or edge case gets an example, pointed to by bold name: `see **"Replaced field"** example below`.
- No unexplained terms ("later field", "the record's own").

### Examples

- Each opens with its bold name and one plain sentence: the situation, and why the result matters. Then a picture of the input (Summary style), then Before and After.
- Before is the result existing code gives for the same input today. Leave it out only when there is no prior equivalent.
- Captured output (logs, exceptions, responses, a command and its output) must come from a real run and goes in a multi-line fenced block; expand compact JSON to one field per line. When only a test shows the behavior, state the result in plain words.
- Use real-looking data, never a test's values. A test can be the proof; don't quote it.
- Every table or log names the symptom it shows. Do not repeat data the Summary shows.
- A threshold that varies with an input (traffic, size) gets a `## <Threshold> by <input>` section before `## Validation / Examples`, holding a Mermaid `xychart-beta` chart: one `line` per rule (before, after), values computed from the formula, x-axis labels like "100", "1k", "10k" for a log scale, and a sentence above naming each line.

## Before returning

- Read the Summary and each example as someone who has never opened the repo: they can say what breaks, for whom, and what this PR changes. Rewrite any sentence whose subject is a class or method name.
- Key terms have the bold label and 2-4 lines.
- Every fenced block spans more than one line.
- No section outside the template, no attribution, no "not run / changed / done / shown" sentence, no hard-wrapped prose.
- Grep the body for `main` (20`, `today`, `now`, `currently` and fix each hit.
- Nothing in the Summary is said again in Changes.

## Final once-over

1. Reread every sentence once as a reader, not against the checklist. Fix or cut any that is false for the example it sits in, says nothing new, contrasts with something that never happens ("instead of X" where X is not real), or stacks two parentheticals.
2. If the harness can start a subagent, give a fresh one only the finished body (not the diff, the facts or this skill) and ask: "Which sentences are false, empty, or do not follow from what comes before? List problems only, most serious first, and leave out any sentence you conclude is fine. Quote each and say why." Check each finding against the code before changing anything.
