---
name: noodle-feed
description: Feed a task source (e.g. Jira epic, project, github project,
  issue links, trello board, etc) into a Noodle project's backlog -
  decomposes it into actionable items, refines each with the user, and
  writes them to brain/todos.md. Use when the user says "feed the epic",
  "add this epic to noodle", "queue up PROJ-123", or points an agent at
  an epic for the noodle loop.
user-invocable: true
argument-hint: "[epic key, tracker URL or path to epic text]"
---

# Noodle Feed

Turn an epic into refined, self-contained items in `brain/todos.md` that the
noodle loop can schedule on its own.

## Step 1: Resolve the project

The target is the cwd or the argument's repo. If `$TARGET/.noodle.toml` or
`$TARGET/brain/todos.md` is missing, say to run `/noodle-init` first and stop.

## Step 2: Read the brain

Read `brain/index.md`, `brain/todos.md` (`next-id`, sections, what is queued),
`brain/codebase/task-sources.md` (how this project reaches its sources) and
`brain/principles/verification.md`.

## Step 3: Get the epic

The argument is a tracker reference (a Jira key or browse URL, a GitHub issue
or PR URL, a Trello card) or a path to task text.

Normalize it before touching any tool. Do not open a tracker URL with a web
fetch (it needs the user's login) and do not pass a URL to a CLI:

- A Jira reference is a key matching `[A-Z][A-Z0-9]+-[0-9]+`, alone or in a URL
  such as `https://<host>/browse/PROJ-123`
  (`grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1`). The project is the part
  before the dash.
- Read it: `jira issue view <KEY> --plain`.
- Children: `jira issue list -p <PROJECT> -q '"Epic Link" = <KEY>' --plain
  --no-headers --columns key,status,summary`. On the Jira recorded for Chat
  Harness, `parent = <KEY>` returns nothing; if `Epic Link` also returns
  nothing, ask which field links children.
- If a URL's host differs from the one in `task-sources.md`, say so and ask.
- Any other tracker: use the method recorded in `task-sources.md`. If none is
  recorded or it no longer works, ask the user how to reach it.
- A path: read the file.

After a successful fetch from a new source or a changed method, update
`task-sources.md` (source, method, credential env var name never its value,
scope, a verified command) and `brain/index.md`.

## Step 4: Decompose

Each item must be actionable by an agent that has never seen the epic: what to
change, where, and what done looks like. One logical change per item.

Check verification before proposing items. Reuse
`brain/principles/verification.md` and ask only what changed: the exact test,
lint and typecheck commands, the runtime check for changed behavior, what does
not count, and any helper script (if one item needs more than two commands, ask
for a helper and record its one command). If there is no note, run the
verification interview from `/noodle-init` Step 4 and write it. An item's Done
line may be more specific than the note, never less.

Shared resources have two parts. The bootstrap (what the user starts or seeds
once per loop session) lives in the project's setup guide, which cooks do not
read. The verification note holds only the cook's read-only check, its
UNVERIFIED label and a hands-off rule. Each affected item's Done line names that
check. If either part is missing for a resource these items need, write it with
the user first. Run the check yourself before writing the items; if it fails,
say so: every such item will stop at that check until the user completes the
bootstrap.

Do not use `#needs_plan` to route an item through planning: it had no effect in
the one order observed (guide §6.5).

Commit hygiene is set up by `/noodle-init` Step 4b; if the project's skill
copies or the `--disallowedTools` list are missing, say so and point there
instead of patching skills here. Skills are copies of the plugin source and are
never hand-patched.

## Step 5: Refine with the user

Show the full proposed list with descriptions. Resolve, in one grouped round:

- Items already done or out of scope.
- Vague Done criteria, or criteria that contradict the verification note.
- The `## Section` each item goes under.
- Scope: which paths each item may edit and which are off-limits (for example
  eval datasets and rubrics when the fix belongs in the agent). A cook sees only
  its own line, and without a scope it may fix a failing check by changing the
  check.

Do not write to `todos.md` before the user approves the list.

Order between items: write a line such as `Order: run only after #N is done`
only where items edit the same code. Such lines keep the scheduler to one order
at a time. Parallel work comes only from separate orders; the stages of one
order always run one after another.

## Step 6: Write the backlog

Per the `todo` skill's format:

1. Read `<!-- next-id: N -->`.
2. Append each approved item as one line under its section:
   `N. [ ] <description> Scope: <allowed / off-limits paths> Done: <criteria> Commit: stage only files you created or edited, by path; never add -A/./*. [url: <source link>]`
   Scope, Done and Commit go on the item line: a cook sees only its own line,
   and `backlog-sync` reads one line per item. `[url: ...]` is the item's
   source as a full `https://` address: for Jira, `https://<host>/browse/<KEY>`
   with the host recorded in `brain/codebase/task-sources.md`; for GitHub, the
   issue or pull request URL. Omit the marker when the host is not recorded or
   the source has no URL. The adapter strips it from the title and passes it
   on, and the scheduler copies it onto the order so its title links there.
   Write each Done line to match the
   verification note:
   - Name the exact command and pass bar (for example the helper and "5/5").
   - Include any precondition from Step 4 (the note's shared-resource check).
   - For a "no change needed" outcome, require the runs the note demands (for
     example a local run and a run against the deployed baseline).
   - Never require writing to an external system (tracker comment, remote
     branch, chat). Say: "write the comment text to `brain/<tracker>/<KEY>.md`
     and quote it in your result; do not post it".
   - If the note says a change class cannot be verified in this setup, give it
     the note's fallback evidence and label, so the stage ends as unverified
     instead of looping.
3. Increment `next-id` past the last used id. Ids are permanent; never
   renumber.
4. Write the lines with the Edit or Write tool, never through a shell string:
   backticks and `$` get mangled there.
5. Re-read the file: each new item is one line with balanced backticks, every
   `brain/<tracker>/<KEY>.md` path is complete and ends in a single `.md`, and
   Scope, Done and Commit are present. Fix and re-read until they are.

## Step 7: Report

- Item count and ids (`#3 - ..., #4 - ...`).
- Tracker comments cooks will write to `brain/<tracker>/<KEY>.md` for the user to
  post.
- Verification note changes and any precondition added.
- If `publish_action` is unset (merge publishing), tracked changes in the root
  checkout block merges; show `git status --short`.
- How the loop will treat each item. In supervised mode every agent stage parks
  for the user's decision; stages in `[review] external_stages` (for example
  `adversarial-review`) hold until `/noodle-review` completes them, and the loop
  looks stalled otherwise; after the last stage a gated order publishes, or
  closes if it has nothing to publish (guide §3.1 "Gated and ungated orders").
- Next: start the loop in a tmux split so the user can watch (Step 8). Never
  `noodle start --once` while orders are queued: it spawns cooks and exits,
  leaving them orphaned and unlogged.

## Step 8: Offer to start the loop

Check whether a loop already runs for this project (`pgrep -fl 'noodle start'`,
`noodle status`, `curl -s localhost:3000/api/snapshot`). If one does, do not
start a second. A running scheduler may not pick up new items at once; check
`noodle status` and the loop pane after about 30 s, and if no scheduler session
starts, offer a loop restart (it schedules at startup). Restart only on yes.
Judge whether the scheduler is idle from its session and the order state, not
from `.noodle/orders-next.json`.

A loop is running only if a `noodle start` process exists; `.noodle/status.json`
can still say `running` after the loop died. Restart only with no cook running:
on start, running stages go back to pending and their retry cleans the worktree
(`git checkout .`, `git clean -fd`), so save `git diff` from any worktree with
uncommitted work first. After editing an adapter, run `bash -n` on it: every
cycle runs the sync adapter, and a syntax error stops the loop.

Before offering to start, run the note's shared-resource check if any item needs it.
If it fails, say which step is missing and that the user runs it first; do not
start the loop, start a bootstrap process or seed anything yourself.

Otherwise ask whether to run `noodle start` now. On no, stop. On yes:

1. If `$TMUX` is set, load `tmux-ctrl` and open a full-height pane on the left at
   20% width in the project dir, keeping a shell after the loop exits:

   ```bash
   tmux split-window -fhb -l 20% -P -F '#{pane_id}' -c "$TARGET" \
     -e NOODLE_PROJECT_DIR="$(cd "$TARGET" && pwd -P)" \
     'noodle start; echo "[noodle exited $?]"; exec $SHELL'
   ```

   Remember the pane id. Without `$TMUX`, give the user the command
   (`NOODLE_PROJECT_DIR=<absolute $TARGET> noodle start`, run from `$TARGET`);
   do not background it from the agent's shell. `NOODLE_PROJECT_DIR` must be the
   absolute path of the directory holding `.noodle.toml` and `.noodle/`, never a
   worktree. Cooks run in worktrees and inherit it; a binary that does not set
   it for cooks otherwise writes their `stage_yield` to the worktree's
   `.noodle/`, and every stage that leaves no commits parks as "ended its turn
   without changes".
2. After about 30 s, capture the pane and run `noodle status` to confirm the
   scheduler dispatched. Check the spawned model with
   `pgrep -fl 'claude --output-format'`.
3. Tell the user where to watch: the pane, `noodle status`,
   `.noodle/sessions/<session>/raw.ndjson`, and the web UI (default
   `http://localhost:3000`). Parked stages are in `.noodle/pending-review.json`
   and the UI's Reviews tab.
4. First-cook check: a few minutes after the first cook starts, read its log
   and report what you find; do not fix it silently:

   ```bash
   grep -ho 'Unknown skill: [a-z-]*\|"permissionMode":"[a-zA-Z]*"\|denied by the Claude Code auto mode classifier' \
     .noodle/sessions/<cook>/raw.ndjson | sort | uniq -c
   ```

   `Unknown skill` means the cook runs without that skill's rules. A
   `permissionMode` other than `bypassPermissions` means the user's settings
   downgrade it and the classifier may block commands; say which were blocked
   and let the user decide. Ask what agents may write outside the repo and make
   sure the items' Scope lines say so.
5. To stop: send `C-c` to the pane, then confirm no
   `claude --output-format stream-json` process is left. Helpers a cook
   started (test runners, a local server) can survive with parent pid 1 in a
   `.worktrees/` directory: list them with `ps -axo pid,ppid,command`, check
   each one's working directory, and stop only those, by pid, after asking.
   Never stop processes by name.
