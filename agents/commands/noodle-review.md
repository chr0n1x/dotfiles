---
name: noodle-review
description: Guide the user through Noodle's review gate one order at a time.
  First run lists every order that needs attention and what each still needs
  (held external reviews, parked stages, publish), the user picks one, and the
  command works that order through all of its external stages (reviewer,
  verdict, accept or reject with rework) until it is published or the user
  stops, then returns to the list. Also briefs stages parked for the user's
  decision against their source ticket. Use when the user says "noodle review",
  "send the reviews out", "what are these pending reviews", or a noodle loop has
  items waiting.
user-invocable: true
argument-hint: "[project path, default: pwd]"
---

# Noodle Review

Work through what needs attention **one order (one cook's work) at a time**:

1. Show every order that needs attention and what each still needs. The user
   chooses one. Never start on an order the user has not chosen.
2. Work the chosen order to the end: parked stages, each external hold in turn,
   rework after a rejection, and the final publish. Read `.noodle.toml` and the
   order's stages to know which external stages are left; loop until none is.
3. When the order is finished, or the user stops, refresh the list and let the
   user choose the next order or stop.

## Turn rule

Every turn is **120 characters or fewer**: one question, one verdict line, or one
status line. No preamble, no recap, no narration of commands; report a command by
its outcome ("accepted, kept at `<branch>`"). The order list is the one exception:
one row per order, each row 120 characters or fewer. Go longer only when the user
picks Chat, types a question, or picks Inspect (the diff, the review, the logs,
the evidence); then answer fully in their terms and return to the open question.

- Every question has 2 to 4 options, recommended first, then "Inspect" and
  "Chat". Labels are a few words; what an option does goes in its description.
- Waits are silent except one line when something changes.
- Errors: one line with the cause and the one next step.
- Never ask for something you can read from the config, the snapshot or the last
  answer.

### Findings table

When the user picks Inspect on a review, or asks to see its findings, show them
as one table, never as prose or a bullet list. One row per finding, in the
review's order:

| # | Finding | Sev | Holds now? | Pick |
|---|---|---|---|---|
| 1 | Inline group keys skip the duplicate check (`handler.go:42`) | high | yes, test shows 2 keys | fix |
| 2 | Docs claim X; code does Y | low | no, fixed in a later commit | skip |

- **Finding:** one plain sentence, with `file:line` where it applies.
- **Sev:** the review's severity, or yours when it gives none.
- **Holds now?:** check each finding against the current code of the branch
  (the PR head, which may be newer than what the cook reviewed) before writing
  the row: read the source, run a test, or say "unverified". Say how you checked
  in a few words.
- **Pick:** your recommendation: `fix`, `doc` (a doc or comment only), `skip`
  (true but not worth it now) or `reject` (wrong); give the reason in a few
  words.

Under the table, one line naming which rows you recommend fixing. The user picks
the rows; fix only those, test first, then rebase the stack above and update the
PR body as for any other change.

## How an order ends here (the publish model)

Background: guide sections 3 "The flow today" and 3.1 "Gated and ungated orders".

- An order is **gated** when `[review] external_stages` is non-empty or
  `publish_action` is set. This command is for gated orders.
- Approving or completing a stage never publishes. It keeps the stage's branch;
  later stages start from it.
- After the last stage: if no kept branch has commits ahead of the integration
  branch, the order **closes by itself** ("nothing to publish; order completed").
  Otherwise auto mode publishes, and supervised mode leaves the order
  **awaiting publish** until `approve-and-publish` (Step 9).
- The publish action is `[review] publish_action`: the `draft-pr` builtin, a
  skill name, or, when unset, a merge of the newest kept worktree into the local
  integration branch.
- With `[review] auto_verify_quality = true`, `quality` is a cook the loop adds
  after every successful execute, not a hold. In this setup the only external
  hold is `adversarial-review`, so after you approve `execute` the next hold comes
  after the quality cook finishes.

The UI matches: every control button shows a spinner until the loop acks and then
the result beside it; in gated orders the approve button reads "Continue to
<next stage>" ("Approve" at the last stage) and Approve & Merge is not shown;
Approve & Publish appears only once an order awaits publish.

## The two queues

Both show in the UI Reviews tab (guide 3.2 "The two review queues"):

- **External holds:** stages named in `external_stages`. Noodle runs no agent for
  them; they are manual in every mode. `noodle review list` shows only these.
  They go to a reviewer the user chooses (Steps 5 to 8).
- **Parked stages:** a cook already ran and its result waits for the user
  (supervised approval, or a cook that ended its turn without changes). They live
  in `.noodle/pending-review.json` and get a briefing (Step 4).

## Step 1: Read the config and build the attention list

```bash
cd "${ARGUMENTS:-$(pwd)}" && grep -nE 'external_stages|extra_stages|publish_action|auto_verify_quality|max_rework|^mode|^\[stages\.|^accept|^reject|^\[hooks\]|^(before|after)(_each)? *=' .noodle.toml
noodle order --help >/dev/null 2>&1 && echo "noodle order: available"
noodle order --help 2>/dev/null | grep -q resolve && echo "noodle order resolve: available"
noodle review list --json
EXT=$(sed -n 's/^external_stages *= *\[\(.*\)\]/\1/p' .noodle.toml | tr -d '" ')
curl -s localhost:3000/api/snapshot | jq -r --arg ext "$EXT" '
  ($ext | split(",")) as $e | .orders[] | select(.id != "schedule") | . as $o
  | ([$o.stages[] | select(.task_key as $k | $e | index($k)) | select(.status != "completed") | .task_key]) as $left
  | "\($o.id)\t\($o.status)\t" + ([$o.stages[] | "\(.task_key)=\(.status)"] | join(" ")) + "\texternal left: " + ($left | join(", "))'
```

`noodle review list --json` prints `{"items": [{order_id, stage_index, task_key,
title, worktree_path, prompt_file}]}`. The `jq` line prints one row per order with
every stage's status and the **external stages still left**. An order is done here
when it has none left and has been published or closed.

If `noodle order` is missing, the binary predates stage completion: use only the
parked-stage steps and say so. If `resolve` is missing, the binary predates stage
outcomes: offer only Continue, Request Changes and Reject in Step 4.

`[stages.<task>] accept/reject` set what happens when a stage of that task
finishes without a human; an unset state parks a stage with changes in
supervised mode. `[hooks]` stages (`after` defaults to `reflect`) never park and
never change the order's result. A stage's `outcomes` in the snapshot are its
verdicts so far (state, action, feedback); show them in the briefing when
present. If the snapshot call fails, the loop is not
running: read `.noodle/pending-review.json` instead and say so. Check for a
`noodle start` process rather than trusting `.noodle/status.json`, which can
still say `running` after the loop died; UI actions then fail with "Failed to
fetch". If `[review]`
still has the replaced `on_quality_accept`, `on_adversarial_review_accept` or
`on_accept` keys, a current binary ignores them; say so.

If a stage parks as "agent ended its turn without changes" although the cook
emitted `stage_yield`, look for the yield in
`<worktree>/.noodle/sessions/*/events.ndjson`: the cook's `noodle event emit`
wrote there instead of the main checkout's `.noodle/`. The loop was started
without `NOODLE_PROJECT_DIR` on a binary that does not pass it to cooks. Say so;
approve the parked stage by hand, and suggest the user restart the loop, once
no cook is running, from the directory holding `.noodle.toml` and `.noodle/`
with `NOODLE_PROJECT_DIR` set to that directory's absolute path.

Read titles and ticket keys from the snapshot and parked reasons from
`pending-review.json`. Give each order a **state**:

| State | How to tell | Next |
|---|---|---|
| HELD | a `noodle review list` item for the order | Steps 5 to 8 |
| PARKED | a `pending-review.json` item whose reason does not start with `external review:` | Step 4 |
| AWAITING PUBLISH | snapshot order `status` is `awaiting-publish` | Step 9 |
| RUNNING | an active stage with no hold or park | wait; say which stage |
| FAILED | order status `failed` | the user's decision; do not touch it |

## Step 2: Show the list and let the user choose one order

One table, one row per order that needs attention: id, ticket key and title,
state, current stage, external stages left. Leave out RUNNING orders but name them
in one line. Ask which order to work on, with a "stop" choice (use the `gate` or
`question` tool, or a plain question). Do nothing for any order until the user
chooses. If nothing needs attention, say so, name any RUNNING orders, and stop.

## Step 3: Decide what the chosen order needs now

Refresh the order from the snapshot and `noodle review list --json`, then:

- PARKED: Step 4, then back here.
- HELD: Steps 5 to 8, then back here.
- AWAITING PUBLISH: Step 9.
- RUNNING (a cook such as quality, reflect or a rework execute): say which stage
  runs and wait (Step 7's wait rules), reporting changes from the snapshot; come
  back when the order parks, holds or finishes.
- Completed (published or closed with nothing to publish) or failed: Step 10.

Loop here until the order has no external stage left and is completed, the user
says stop, or noodle leaves it for a human decision.

## Step 4: Brief and decide a parked stage

The item in `.noodle/pending-review.json` has `order_id`, `stage_index`,
`task_key`, `title` (leads with the ticket key), `session_id`, `worktree_path` and
`reason`. The same list is `pending_reviews` in `GET /api/snapshot`; the file works
when the server is down. The diff is `GET /api/reviews/<id>/diff` or the
worktree's `git diff`.

Gather, read-only:

1. **The ticket:** its line in `brain/todos.md` (description, Scope, Done) and,
   when `brain/codebase/task-sources.md` records a method, the ticket itself (for
   Jira, `jira issue view <KEY> --plain`). Never write to the tracker.
2. **What the cook did:** the final `result` entry in
   `.noodle/sessions/<session_id>/raw.ndjson`, `git log --oneline main..HEAD`,
   `git diff --stat main...HEAD` and `git status --short` in the worktree.
3. **Evidence it cites:** open the logs or paths it names when the briefing
   depends on them, and say if you could not. When `brain/codebase/reviewing.md`
   exists, gather what it asks for, opened the way it says (for example trace
   links). Never build a link from anything else.

Give a one-line briefing: ticket, what the cook did or why it parked, and your
recommendation. Evidence (pass counts, what a failing check compares, what you did
not verify) stays behind Inspect.

- When the work looks sound, recommend **Continue to <next stage>** (the `approve`
  action): it starts the next stage and keeps the branch; nothing is published.
- When the stage parked with no work, for example an `UNVERIFIED:` result
  because a precondition failed, recommend **Leave parked**. Continuing still runs every later stage
  (the quality cook, the external review, reflect) on empty work, then closes with
  nothing to publish (guide 6.6.5 "Approving an empty parked stage runs the rest
  of the order").

Ask: Continue, Request Changes (with feedback text the user may edit), Reject,
Leave parked, Resolve, Inspect, or Chat (offer at most four plus Inspect and
Chat; pick the four that fit and put the rest under Resolve). Option
descriptions:

- Continue: next stage starts; branch kept.
- Request Changes: in a gated order, re-runs this stage in its worktree with the
  feedback, counted against `max_rework`; the order fails only at the limit. In an
  ungated order it fails the order (the worktree is kept).
- Resolve: any verdict (accept or reject) with any action, plus feedback that
  is recorded on the stage and shown to every later stage, reflect included:
  - `promote`: the next stage runs; a reject still fails the order at its end,
    after the later stages (for example adversarial-review) and reflect ran.
  - `exit`: the remaining work stages are skipped and reflect still runs; an
    accept completes the order, a reject fails it with the feedback, worktree
    kept.
  - `park`: stays parked with the verdict recorded.
  - `retry`: this stage runs again in its worktree with the feedback.
  - `retry-previous`: the stage before it runs again with the feedback, then
    this stage again ("send back to sender").
  Retries count against `max_rework`; at the limit the order fails, worktree
  kept.
- Reject: fails the order; the scheduler reads it as bad work and may stop
  scheduling until told otherwise (guide 6.5.1 "The scheduler goes idle"). When
  the user means "cancel", not "wrong", say so to the scheduler right away, with
  what to schedule next, while its session is live. A message sent when no
  scheduler session runs starts a new one, and whether queued orders survive
  that is unverified.

The same actions are in the UI, except Resolve; offer both. Only on an explicit
choice:

```bash
curl -s -X POST localhost:3000/api/control -H 'content-type: application/json' \
  -d '{"action": "<approve|request-changes|reject>", "order_id": "<id>", "prompt": "<feedback, request-changes only>"}'
```

For Resolve, write the agreed feedback to a file and run, from the project
root (it waits for the ack and exits non-zero on an error ack):

```bash
noodle order <id> resolve <task_key> <accept|reject> <promote|exit|park|retry|retry-previous> --feedback-file <file>
```

The response has an `id`; read the result with `curl -s
localhost:3000/api/control/<id>` (404 "ack pending" means not processed yet; retry
for about 30 s). `ok` only means accepted: re-read `pending-review.json` and say
whether the item left the queue, and after `approve` name the kept branch from the
ack. `approve` is refused on an external hold. Return to Step 3.

## Step 5: Pick the reviewer for this order

List only targets that exist now and say what was found. Ask once per order; the
answer covers every later hold of this order in this run, including the repeat
after a rework. Ask again only if the target is gone.

- **Neovim terminal buffers** (when `$NVIM` is set; load `nvim-ctrl`):

  ```bash
  nvim --server "$NVIM" --remote-expr 'luaeval("vim.json.encode(vim.tbl_map(function(b) return {buf=b, name=vim.api.nvim_buf_get_name(b), chan=vim.bo[b].channel} end, vim.tbl_filter(function(b) return vim.bo[b].buftype == [[terminal]] and vim.bo[b].channel > 0 end, vim.api.nvim_list_bufs())))")'
  ```

  Drop this process's own terminal (`vim.env.NVIM` match plus `$PPID` ancestry via
  `vim.fn.jobpid(chan)`) when it can be identified; if not, list it and say so. A
  buffer id goes stale when a terminal restarts; look it up again before sending.
- **tmux panes** (when `$TMUX` is set; load `tmux-ctrl`):

  ```bash
  tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_name} #{pane_current_command} #{pane_title}'
  ```

  Exclude `$TMUX_PANE`.
- **New tmux window with a named CLI:** offered when `$TMUX` is set. The user
  names the CLI; do not suggest one. Check `command -v <cli>`; if missing, say so
  and ask again. Do not install anything.
- **This session:** always offered. If the user picks it ("you take it"), send
  nothing: read the prompt file and do the review yourself in the held stage's
  worktree under the Step 6 rules, then continue at Step 7.

With neither `$NVIM` nor `$TMUX`, offer only this session; if declined, print each
`prompt_file` path for the user to run by hand, and stop.

## Step 6: Send

Send a short message, not the whole prompt:

```
You are being invoked as an external reviewer, in place of codex. The
review prompts and skills may tell you to run the opposite model's CLI
(`codex exec`) or to spawn other reviewers; codex is not installed or
available here, so do not call it. Perform each lens or step yourself, as if
you were codex, and do not describe that as a shortfall in your review. Your
skills are not preloaded and you have no Skill tool: open the files named
below and follow them as written, using your own tools.
Read and follow <prompt_file>. Work in <worktree_path>.
Write your review to <review_path> and end it with exactly one line:
VERDICT: accept   or   VERDICT: reject
If you reject, put what the work agent must change under a heading
"## Feedback for the agent", specific enough to act on without this review.
Do NOT run `noodle order ... complete`; the user's orchestrating agent
completes the stage after the user has seen the verdict. Stop when the file is
written.
```

`<review_path>` is `brain/reviews/<order_id>-<task_key>.md` in the project root
(`brain` is linked into every worktree).

- **Before any send,** read the target's input line (`tmux capture-pane`, or
  `nvim_buf_get_lines` on the terminal buffer). Send only when it is empty; if
  the user may be typing there, ask first. Two senders at once interleave
  (guide 6.7.5 "Shell traps and agent terminals").
- **New window:** `tmux new-window -d -P -F '#{pane_id}' -n "review-<order_id>" -c
  "<worktree_path>" '<cli>'`. Capture until the CLI shows its prompt (about 30 s);
  if it never does, show the capture and ask. Then send as for a pane.
- **tmux pane:** send the message literally, then Enter as a separate call.
- **Neovim terminal:** `chansend(<channel>, <message>)` as one line (a newline
  submits), then `chansend(<channel>, "\r")`. Some CLIs need a second Enter after
  a long message.

For the full prompt instead, use bracketed paste (`tmux paste-buffer -p`, or
`\27[200~` ... `\27[201~` with chansend) in chunks of a few KB, then Enter.

After sending, capture the target and confirm the reviewer started. Tell the user
what was sent, to which target, for which order and stage. If it did not land, say
so and ask; do not resend blindly.

## Step 7: Wait for the verdict and put it to the user

Do not sleep in the foreground; the tool blocks it. Use `Monitor` with an
until-loop that prints a line when `<review_path>` has a `VERDICT:` line, or when
the hold leaves `noodle review list`. Without `Monitor`, use one foreground call
per wait (`until ...; do sleep 15; done` for a few minutes) and repeat. Never end
your turn while a wait runs. The user may say "stop watching" (`TaskStop`), which
leaves the hold and the reviewer alone.

On a verdict, give a one-line briefing in the ticket's terms: verdict, whether the
Done criteria are met, your recommendation. Findings and evidence stay behind
Inspect. Ask: Accept, Reject, Leave held, Inspect, or Chat. Never record a verdict
without that answer.

If a hold disappears with no file or verdict, the reviewer completed it itself:
run `noodle review show <order> --json`, report the verdict, and return to Step 3.

## Step 8: Complete the stage by name, then check what is left

The stage name is the hold's `task_key`. Noodle refuses a name that does not match
the held stage; the error names the held stage and the command to use.

```bash
noodle order <order_id> complete <task_key> --file <review_path> [--reject]
```

It waits up to 30 s for the loop's ack and prints it (`--no-wait` skips the wait);
a non-zero exit is an error ack: show the output.

- **Accept:** no flag. The stage completes without publishing and the ack names
  the kept branch. Confirm the order moved on.
- **Reject:** show the findings, draft the feedback for the work agent from the
  `## Feedback for the agent` section, and let the user edit it. Say in the
  feedback whether the agent may change files outside the item's Scope; the user
  decides. Write the agreed text into the review file, then run with `--reject`.
  Noodle inserts a rework `execute` with that feedback and a copy of the review
  stage, up to `[review] max_rework` rounds (default 2), and the ack says which
  round. At the limit, or with no earlier execute stage, the stage re-parks with
  the feedback as a blocking message: tell the user it needs a decision (Step 4).
- **Other outcomes:** to end the order now ("you hallucinated this; it is not
  possible"), or to accept and continue regardless, use
  `noodle order <order_id> resolve <task_key> <accept|reject> <action> --feedback-file <review_path>`
  with the Step 4 actions instead of `complete`.

Then re-run the Step 1 query for this order:

- External stages left: the next hold comes after the cooks before it (rework
  execute, quality); go to Step 3 and repeat Steps 6 to 8 with the same reviewer.
- None left: go to Step 3; the order closes by itself, publishes in auto mode, or
  waits for Step 9.

Do not start or stop the noodle loop.

## Step 9: Approve and publish

Only for an order that is awaiting publish. In auto mode noodle publishes by
itself; just report it (Step 10).

Brief in one line: commits to publish and the action, for example `4: 2 commits ->
draft-pr. Publish?`. Behind Inspect: the verdicts, `git log --oneline main..<kept
branch>` (the branch is in the last ack and `.noodle/order-work.json`), and that
`draft-pr` or a publish skill pushes and opens a PR, which a permission mode may
deny, while the default merge does not push.

Ask: Publish, Leave it, Inspect, or Chat. Only on an explicit yes:

```bash
curl -s -X POST localhost:3000/api/control -H 'content-type: application/json' \
  -d '{"action": "approve-and-publish", "order_id": "<id>"}'
```

Read the ack. A refusal names what is not done; show it and do not retry. On
success the action runs (a skill runs as a final stage and can take minutes):
watch the snapshot until the order completes and report the result (the PR link,
"merged", or "nothing to publish"). A failed publish leaves the order awaiting
publish with the error in the order's `publish_error`; report it and ask, do not
retry on your own. `publish_blocked_reason` says why a publish would be refused
now.

## Step 10: Report on this order, then return to the list

One line: id, what was published and where (PR link, merged, or nothing to
publish), and where the order is now (completed, reworking, awaiting publish,
parked, failed). Review files, verdicts, feedback sent and anything not verified
stay behind Inspect.

Go back to Step 1, refresh, and return to Step 2 for the next order or stop.
