---
name: noodle-distill
description: Distill general, cross-project learnings from a Noodle project's
  local brain/ vault into the user's global Obsidian vault. Use when the user
  says "distill the brain", "promote these learnings", "save what we learned
  from this project", or after a Noodle project is winding down.
user-invocable: true
argument-hint: "[target project path, default: pwd]"
---

# Noodle Distill

Promote durable, cross-project knowledge from a Noodle project's `brain/`
vault (personal, gitignored, disposable) into the user's global Obsidian
vault (durable). The project brain is a scratchpad; this is how the
generalizable bits survive it.

## Step 1: Resolve sources and guard

```bash
TARGET="${ARGUMENTS:-$(pwd)}"
cd "$TARGET" || exit 1
[ -d brain ] || { echo "no brain/ vault here - run /noodle-init first"; exit 1; }
echo "OBSIDIAN_VAULT_PATH=${OBSIDIAN_VAULT_PATH:-<unset>}"
```

The global vault is wherever `$OBSIDIAN_VAULT_PATH` points - the same var
the `obsidian-*` skills use. Do not hardcode a path. The variable is often
unset in an agent's shell even when the user's interactive shell has it. When
it is unset, ask the user for the vault path (offer any `.obsidian/` parent
found with `find ~ -maxdepth 4 -type d -name .obsidian 2>/dev/null`, as
options only). Then check it:

```bash
VAULT="<answer, with a leading ~ expanded to $HOME>"
[ -d "$VAULT/.obsidian" ] || { echo "$VAULT is not a vault (no .obsidian/)"; exit 1; }
```

Prefix every `obsidian-*` skill call and shell command in this run with
`OBSIDIAN_VAULT_PATH="$VAULT"` (each Bash call is a fresh shell, so an
`export` does not carry over). Tell the user once to export it in their shell
profile.

## Step 2: Survey the project brain

List everything first: `find brain -name '*.md' -not -path 'brain/plans/*'
-not -path 'brain/archive/*' | sort`. Read `brain/index.md`, then every
listed file except `brain/todos.md`. Noodle's `reflect` and `meditate` hooks
write to more places than `codebase/` and `principles/` (for example
`reviews/`, `delegation/`, `audits/`, topic folders of their own), so do not
limit the survey to a fixed folder list. Skip `brain/plans/`, `brain/archive/`
and `brain/todos.md` - those are project-transient by definition (a finished
plan and a done backlog item are history, not reusable knowledge). Review
files under `brain/reviews/` are per-order; mine them only for findings that
repeat across orders.

Also check what the user taught the loop: a project-local `.agents/skills/`
that differs from the noodle copy (`diff -rq`), or a
`[stages.<task>] system_prompt` in `.noodle.toml`. List those as candidates
too.

## Step 3: Distill - the judgment

A note is **distillable** if it would improve how you work on a *different*
project. The test, per the `brain` skill, inverted: "would this help on a
project that has none of this codebase's context?"

Distill:
- **Tooling gotchas** not about this codebase - "ast-grep chokes on X
  syntax", "the tmux popup approach hangs when Y", "this provider's CLI
  needs Z flag or it blocks"
- **Process principles** that generalized - "propose-then-approve kept the
  backlog clean across 3 epics", "parallel stages only for independent
  packages"
- **Recurring patterns** - "this class of bug kept appearing; the fix was
  always Z"

Do NOT distill:
- Codebase-specific facts - "the auth middleware has a race" (stays in the
  project brain, or dies with it)
- Stack decisions - "we use chi not gin" (a decision about *this* project's
  stack)
- Plan content, backlog items, session history

When in doubt, leave it. A global vault polluted with project trivia is
worse than an empty one.

## Step 4: Deduplicate against the global vault

For each candidate, use `obsidian-read` to search the global vault for the
topic (search term, then `--tag` if the candidate maps to an existing tag).
- **No match** -> propose a new note via `obsidian-create`.
- **Match exists** -> propose a merge via `obsidian-update`: fold the new
  learning into the existing note, don't create a sibling.

## Step 5: Propose + approve

Show the full list before writing anything:

- Each candidate: the distilled text (bullets, plain markdown, under ~50
  lines - the `brain` skill's own constraints), the destination path in the
  global vault, and for merges, the diff against the existing note.
- A one-line provenance backref per candidate: "distilled from
  `<project>/brain/codebase/<file>.md`" - included in the note body so the
  global vault stays auditable. The backref points at a gitignored file, so
  it is a machine-local pointer, not a durable link - that is expected.

Ask for approval. Revise on feedback. Do not write to the global vault
before the user approves the list.

## Step 6: Write and report

Apply the approved `obsidian-create` / `obsidian-update` calls. Report:
- N notes created, M notes updated
- What was deliberately left in the project brain (one line, so the user
  knows the culling was deliberate)

Do not delete from the project brain - it is disposable, but the user may
still be working in the project.
