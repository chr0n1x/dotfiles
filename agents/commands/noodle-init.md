---
name: noodle-init
description: Set up Noodle (skill-based agent orchestration) for a project -
  interviews the user on the per-order pipeline (stages, goals, finished
  product, publish), then scaffolds .noodle/, .noodle.toml, the brain vault,
  backlog adapters, and the loop skills from the vendored submodule and the
  user's own skills. Use when the user says "init noodle",
  "set up noodle", "start a noodle project", or asks to run noodle in this repo.
user-invocable: true
argument-hint: "[target repo path, default: pwd]"
---

# Noodle Init

Set up Noodle for one project. The goal: the user later hands `/noodle-feed`
a link, the items land in the backlog, and cooks take any order through the
stages agreed here to a published result, stopping only at holds the user
chose. Init gets there by interviewing the user on the pipeline (Step 2b)
before it writes any config.

The vendored checkout at `agents/tools/noodle` in the
dotfiles repo (NOD) is the source for skills and adapters: copy them, never hand-patch the
copies. A change every project needs goes into the plugin source and is copied
again; project-specific rules live in `brain/principles/`.

The end state is config, copied skills, executable adapters, a backlog, an MCP
allowlist for Claude cooks, a verification note, standing-permission and
model-routing notes, agreed helper scripts, task-source notes and index links.
Init never installs without permission, starts the loop, discards work without
asking, or creates credentials.

A project's setup guide (`brain/noodle-setup-and-footguns.md`), where one
exists, is the worked example referenced below; other projects may not have one.

## Step 1: Resolve target and check preconditions

```bash
TARGET="${ARGUMENTS:-$(pwd)}"
cd "$TARGET" && git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  { echo "not a git repo"; exit 1; }
```

Use the repository root as TARGET. Derive every dotfiles path from this command
file, never from a hardcoded home path. Take the path the harness loaded this
file from (a `commands/noodle-init.md` or `skills/noodle-init/SKILL.md` link)
and resolve it with `readlink -f`; the real file lives in `<agents>/commands/`:

```bash
SELF="$(readlink -f "<path this file was loaded from>")"
AGENTS="$(cd "$(dirname "$SELF")/.." && pwd -P)"
NOD="$AGENTS/tools/noodle"
USER_SKILLS="$AGENTS/skills"
```

Check `$NOD/.agents/skills/schedule/SKILL.md` and `$USER_SKILLS` exist; if not,
ask for the agents directory. Do not initialize or update a submodule without
permission.

Read project instructions and inventory existing `.noodle.toml`, brain, skills
and adapters. On a rerun, show proposed changes and ask before overwriting;
preserve the backlog and show skill-copy differences before replacing them.
Record `git -C "$NOD" rev-parse HEAD`. Tell the user what was found.

### Step 1b: Binary

```bash
command -v noodle && noodle --version
cat "$NOD/VERSION"
```

**Existing install:** use it if it runs. Report path, version and any difference
from the source; offer a rebuild, never do it unasked. A stale symlink counts as
zero install. Check `noodle --help`, `noodle order --help` and
`noodle review --help`, the `[review]` keys in `$NOD/config/fork.go`, and the
`[stages.<task>]` and `[hooks]` keys in `$NOD/config/outcome.go`, for the
features the user needs (external holds, `noodle order <id> complete <stage>`,
`noodle order <id> resolve`, `approve-and-publish`, `auto_verify_quality`,
stage outcomes, per-stage harness/model/system prompt, hooks, worktree links).
A binary without `resolve` in `noodle order --help` predates stage outcomes and
hooks: it ignores `[stages]` and `[hooks]`. This command was
written against plugin `main` at `2c2cd29`; the installed binary may be older.
If a required command or key is missing, name it and ask whether to rebuild or
defer. Help shows what exists, not that it works.

**Build (zero install or approved rebuild):** downloads pinned pnpm and npm
packages, so ask first. Require `go`, `node`, `corepack` on PATH; do not install
them. The binary embeds `ui/dist/client`, so build the UI first; plain
`npm install` does not work for this pnpm workspace. Build to a new file and
rename it over `bin/noodle`, keeping a dated backup, and only while no cook or
scheduler session runs (`ps -axo pid,command | grep 'claude --output-format'`
shows none, or the loop is stopped):

```bash
cd "$NOD"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
corepack pnpm install --frozen-lockfile
corepack pnpm --filter noodle-ui build
go build -o bin/noodle.new .
[ -f bin/noodle ] && cp -p bin/noodle "bin/noodle.bak-$(date +%Y%m%d-%H%M)"
mv -f bin/noodle.new bin/noodle
GOBIN_DIR=$(go env GOBIN); ln -sf "$NOD/bin/noodle" "${GOBIN_DIR:-$(go env GOPATH)/bin}/noodle"
noodle --version
```

Confirm the bin dir is on PATH. A running loop keeps the old binary until it is
restarted. On TLS, 401/403 or registry errors, stop and ask where credentials or
CA certs live; use them for this build only, in a throwaway mode-600 npm config
selected with `NPM_CONFIG_USERCONFIG`, never `~/.npmrc`, and ask before exporting
keychain certificates for `NODE_EXTRA_CA_CERTS`. On any other new failure, stop
and ask. Do not stage build outputs or alter existing source changes.

## Step 2: Scaffold the project state

Create missing `.noodle`, `brain/plans`, `brain/archive`, `brain/principles`.
Add missing entries to the repository's info/exclude file (resolve it through
Git for linked worktrees), not the tracked `.gitignore`:

```text
.noodle/
brain/
.worktrees/
.agents/
adapters/
.noodle.toml
```

Ask first whether the user wants to commit any of these instead. Exclusions do
not hide files already tracked.

Seed `brain/todos.md` only if missing:

```markdown
# Todos

<!-- next-id: 1 -->

## Inbox
```

Seed `brain/index.md` only if missing, and keep it current through every later
step: add a line each time init writes a brain note, a helper script or a
decision the user makes. `brain/` is excluded from Git, so the index is local
only and may point at anything on this machine by absolute path.

```markdown
# Brain Index

## Notes
- [[principles/verification]] - <one line>

## On this machine
- `<absolute path>` - <what it is and when the user needs it>
```

"Notes" lists brain files. "On this machine" lists what the project's setup
relies on outside the repo: runbooks, sibling repos, deploy configuration,
local service files. It does not list the tooling that builds `brain/` (these
commands, the user's skills, the noodle plugin or its source) or the user's
own notes and backup folders. Cooks read the index, so describe entries as
context and keep the hands-off rule in the verification note; never list a
credential's value, only where it lives.

Copy `backlog-sync`, `backlog-add`, `backlog-done`, `backlog-edit` from
`$NOD/defaults/adapters/` to `adapters/` (keep approved local edits), `chmod +x`
them, and change `NOODLE_TODOS_FILE:-todos.md` to
`NOODLE_TODOS_FILE:-brain/todos.md` in the copies, or the adapters see an empty
backlog. After any adapter edit run `bash -n adapters/<name>`: a syntax error
stops the whole loop at the next backlog sync.

## Step 2b: Interview the pipeline

Ask about outcomes before validation steps. Read an existing
`brain/principles/pipeline.md` first and ask only what changed. One topic per
question, in this order:

1. **Kinds of work.** What will the user feed in (bug fix, feature, docs,
   investigation, dependency bump, ...)? Each kind may get its own stage list.
2. **Finished product per kind.** What exists when an order is done: a draft
   PR, a pushed branch, a merge into the local integration branch, a report or
   diagnosis in `brain/`, a drafted tracker comment? Who looks at it next?
3. **Stages per kind, in order.** For each stage:
   - skill (Step 4 lists noodle's and the user's; a stage may use either),
   - goal in one sentence: what this stage is for, not how it validates,
   - input it reads and output it hands to the next stage (commits, a plan in
     `brain/plans/`, a review file, a `stage_message`),
   - accept and reject: what counts as each, and what happens on reject
     (`retry`, `retry-previous`, `park`, `exit`; Step 3 "Stage outcomes"),
   - who decides: the cook by itself, an external hold, or the user,
   - harness and model when it should not be the scheduler's choice.
4. **Hooks.** Anything that runs before or after every order or every stage.
5. **Publish.** One `publish_action` serves the whole project (`draft-pr`
   builtin, a skill, or unset for a local merge). If kinds need different
   endings, express the difference as stages (for example a report kind whose
   last stage writes to `brain/` and leaves no commits, so it closes with
   nothing to publish).
6. **Autonomy.** Which stages may move on without the user. Supervised mode
   parks every stage with changes unless `[stages.<task>] accept = "promote"`;
   `mode = "auto"` promotes and publishes by itself. Agree which the user
   wants and where the remaining human gates sit.

Write `brain/principles/pipeline.md` (no frontmatter, about 60 lines) and
add it to the index. `/noodle-review` audits cooks against it, so make each
stage checkable:

```markdown
# Pipeline

Publish: <publish_action and what it produces>
Autonomy: <mode; human gates>

## <kind>
Match: <name used in the backlog item's `Kind:` field; other hints such as source or title prefix>
Finished: <the artifact and where it lives>
1. <skill> - <goal>. In: <input>. Out: <output>. Accept: <criteria>. Reject: <criteria> -> <action>. Decided by: <cook|hold|user>.
2. ...
```

The scheduler builds every order's stages, and its `schedule` skill does not
read this note on its own. Step 3 adds `[stages.schedule] system_prompt`
pointing it here. Whether `[stages.schedule]` reaches the scheduler session is
unverified: after the first loop start, check the scheduler's prompt under
`.noodle/sessions/schedule-*/` for the text. If it is missing, offer the
user's own `schedule` skill (Step 4 substitution) that reads the note first.

The stages the user picks drive Step 3: `[review]` (extra and external stages,
publish), `[stages.<task>]` (outcomes, harness, model, system prompts) and
`[hooks]`. Where a choice does not fit noodle's keys, say so plainly and
agree a workaround; do not drop it silently.

## Step 3: Write .noodle.toml

Show the user the proposed config before writing anything. Start from these
defaults, fill in what you can already tell (an existing `.noodle.toml`, the
repo's remotes, earlier answers), and mark the rest as `<placeholder>`. Present
the whole file, then go through it one table at a time: say in a line what the
table does (the bullets below), show its proposed lines, and ask what the user
wants, keep, change or drop. Write the file only after the user approves the
final version, then show what was written.

```toml
mode = "supervised"

[routing.defaults]
provider = "claude"
model = "<confirmed model>"

[skills]
paths = [".agents/skills", "<absolute $USER_SKILLS>"]

[adapters.backlog]
skill = "todo"

[adapters.backlog.scripts]
sync = "adapters/backlog-sync"
add = "adapters/backlog-add"
done = "adapters/backlog-done"
edit = "adapters/backlog-edit"

[concurrency]
max_concurrency = <n>          # suggest 2 for the first run, then raise
exclude_scheduler = true

[agents.claude]
exit_after_turn = true
args = [
  "--add-dir", "<absolute repo>/brain",
  "--add-dir", "<absolute $AGENTS>",
  "--strict-mcp-config", "--mcp-config", "<absolute repo>/brain/agent-mcp.json",
  "--disallowedTools",
  "Bash(git add -A*)", "Bash(git add --all*)",
  "Bash(git add .)", "Bash(git add . *)",
  "Bash(git commit -a*)", "Bash(git commit --all*)",
]

[worktree]
link = ["brain", "adapters", ".noodle.toml", ".agents"]
diff_against_local_only = true

[delivery]
push_remote = "<remote>"
pr_repo = "<owner/repo>"
base = "<base branch>"

[review]
auto_verify_quality = true
external_stages = []
extra_stages = ["adversarial-review"]
max_rework = 4
publish_action = "draft-pr"

[stages.adversarial-review]
harness = "claude"
model = "claude-opus-5-5"
accept = "promote"
reject = "retry-previous"
system_prompt = """
The adversarial-review skill says to spawn reviewers on the opposite model with `codex exec` or `claude -p`. Ignore that requirement. Run every reviewer with pi on GitHub Copilot's gpt-6.1-sol instead, one call per lens, from the worktree:

pi -p --no-session --provider github-copilot --model gpt-6.1-sol --tools read,bash "<prompt>" < /dev/null > "$REVIEW_DIR/<lens>.md" 2>/dev/null

Build each prompt from references/reviewer-prompt.md as the skill says. Start every lens in ONE foreground Bash call, each pi command ending in `&`, and end that call with `wait`, so the call returns only when all reviewers are done:

pi ... > "$REVIEW_DIR/skeptic.md" 2>/dev/null & pi ... > "$REVIEW_DIR/architect.md" 2>/dev/null & wait

Give that call a timeout of at most 10 minutes (600000 ms). Do not set run_in_background, do not use Monitor, and do not end your turn while a reviewer runs: your session closes when your turn ends, and the stage then counts as finished without a verdict. In Step 4, log reviewer_cli=pi. Do not describe this substitution as a shortfall in the verdict.

After Step 5, end the stage with exactly one stage_message, decided by your Lead Judgment. Emitting it is your last action; never end your turn without it:

- Reject when you accepted at least one high-severity finding. The message goes to the execute agent that reworks the change, so write it for that agent: each accepted finding with file:line, what is wrong and the concrete change to make. Leave out findings you rejected.
  noodle event emit --session $NOODLE_SESSION_ID stage_message --payload '{"message": "<feedback for the execute agent>", "blocking": true}'
- Accept otherwise, with a one-line summary of the verdict:
  noodle event emit --session $NOODLE_SESSION_ID stage_message --payload '{"message": "<summary>", "blocking": false}'
"""

[stages.schedule]
system_prompt = """
Before scheduling, read brain/principles/pipeline.md. Match each backlog item to one kind by its `Kind:` field, else by the kind's Match line, and build the order's stages exactly as that kind lists them, with each stage's goal, input, output and accept criteria in its extra_prompt. When no kind matches, use the default pipeline from your skill and say so in the order rationale.
"""

[hooks]
after = ["reflect"]
```

Every table below comes from the Step 2b answers; the template only shows the
shape. Drop `[stages.adversarial-review]` when no kind uses that stage.

- **Provider and model:** `claude` or `codex`. Verify the model before writing it
  (`claude -p --model <id> "reply with ok"`; ask before paid calls). The scheduler
  picks per-stage models from the `schedule` skill's routing table; to pin one
  model everywhere write `brain/principles/model-routing.md` (one row and "do not
  route to any other model"), which the skill reads first.
- **Concurrency:** suggest 2 cooks and ask whether the user wants more (or 1,
  when cooks share an account or a service). `exclude_scheduler = true` keeps
  the scheduler from taking a cook slot. Claude cooks need
  `exit_after_turn = true`, or a session waits after its turn ends.
- **Delivery:** confirm push remote, PR repository and base branch, then write
  `[delivery]` with `push_remote`, `pr_repo`, `base`. Do not assume a fork.
- **Review policy:** keep mode supervised. Ask which stages wait for an external
  reviewer, which extra stages to add, how many rework rounds to allow, whether
  the loop should always run a quality cook after execute, and how a finished
  order is published. The default (the template's `[review]`) runs
  `adversarial-review` as a cook inside the loop after quality, and
  `[stages.adversarial-review]` decides what its verdict does (next bullets).
  `publish_action` keeps the order gated, so `auto_verify_quality` applies.
  Without `publish_action` and with `external_stages = []` the order is
  ungated: `auto_verify_quality` is ignored (the config check warns) and no
  quality cook runs after execute. The alternative holds the review for a
  reviewer the user picks through `/noodle-review`, with no agent:
  `external_stages = ["adversarial-review"]`; then drop
  `[stages.adversarial-review]`, since no cook runs it.

  What each key does (verify against `config/fork.go`):
  - `auto_verify_quality`: after each execute succeeds the loop inserts a
    `quality` stage run as its own cook; a blocking reject sends execute back as
    rework. Only in gated configs; default false.
  - `external_stages`: stages held with no agent until
    `noodle order <id> complete <stage> --file <review.md> [--reject]`; the stage
    name must be the held task key. Accept never publishes. `[]` for none.
  - `extra_stages`: skills added to every order after its quality stage, in list
    order, when the order is promoted; existing names are not duplicated and
    unknown names are skipped. Orders already promoted are not changed. Leave
    `reflect` out: it is the default `[hooks] after` hook now, and an older
    config that lists it here only gets it once.
  - `max_rework`: rework rounds per order, shared by quality rejects, external
    rejects and Request Changes; default 2, 0 disables.
  - `publish_action`: `draft-pr` (builtin: push `noodle/<order>` and open or
    update a draft PR; needs `[delivery]`), a skill name (a final agent stage), or
    unset (merge the newest kept work into the local integration branch). Ask
    before setting it.

  An order is gated when `external_stages` is non-empty or `publish_action` is
  set; ungated orders behave as upstream noodle. In a gated order, approving a
  parked stage only continues to the next stage, publishing happens once after
  the last stage, and an order with no commits to publish completes without
  publishing. Request Changes re-runs the stage with the feedback in gated
  configs and fails the order (keeping the worktree) in ungated ones. Details:
  the guide's §3.1 "Gated and ungated orders" and §3.3 "Reject, rework and
  Request Changes".
- **Stage outcomes:** the template's `adversarial-review` promotes on accept
  and sends execute back with its feedback on reject. Ask whether to keep that
  and whether any other task should act on its own; write the answers as
  `[stages.<task>] accept` and `reject` (verify against
  `$NOD/docs/reference/configuration.md`). Actions:
  `promote` (next stage runs, branch kept, nothing merged), `exit` (skip the
  remaining work stages; `after` hooks still run; a reject fails the order),
  `park` (wait for `noodle order <id> resolve`), `retry` (re-run this stage
  with the feedback), `retry-previous` (re-run the work stage before it with the
  feedback, then a copy of this stage). Both retries count against
  `max_rework`; at the limit the order fails and the worktree is kept. Two
  rules the user needs before choosing:
  - An unset state keeps the mode's behavior, and supervised mode parks every
    finished stage, so a stage that should move on by itself needs
    `accept = "promote"` even in supervised mode.
  - A stage is rejected when its cook fails or ends with a blocking
    `stage_message`, whose text becomes the feedback. A skill that never emits
    one always reads as accepted: `quality` emits it, `adversarial-review` does
    not, so a `reject` on it never fires unless `system_prompt` (next bullet)
    adds that step.
- **Per-stage cook and skill wrapping:** `[stages.<task>]` also takes `harness`
  (`claude` or `codex`) and `model`, which replace the scheduler's choice on
  stages that have not started; `provider` (codex's `model_provider`, only with
  `harness = "codex"`); and `system_prompt`, text placed after the skill in the
  cook's system prompt so it can override one of the skill's instructions.
  Skills are copies and never hand-patched (Step 4), so `system_prompt` is how
  a project changes one. The template's `adversarial-review` defaults: an
  opus cook (a different model from execute's, for a second opinion) whose
  reviewers run through pi on `github-copilot` / `gpt-6.1-sol`, and a
  `system_prompt` in two parts. Ask whether to keep each:
  - **Reviewer swap** (first paragraphs): replaces the skill's `codex exec` /
    `claude -p` requirement with one reviewer command. To keep the skill's own
    CLI, delete these paragraphs; for another CLI, provider or model, rewrite
    the command and the `reviewer_cli=` value. Before writing it, check the
    CLI exists (`command -v`), list its models (for pi,
    `pi --list-models <search>`), check auth (for pi,
    `pi auth check --provider <p> --model <m>`), and run the exact command
    once from the repo with a trivial prompt after the user agrees, since it
    may be a paid call. Never install a CLI. Keep the "one foreground Bash
    call ending in `wait`" rule: with `exit_after_turn = true` a cook that
    starts its reviewers in the background, or waits on them with `Monitor`,
    ends its turn and its session closes before it records a verdict.
  - **Verdict step** (last paragraph): ends the stage with one
    `stage_message`, blocking with feedback for the execute agent when the
    cook accepts a high-severity finding, non-blocking otherwise. Keep it
    whenever `reject` is set. A stage with `reject` set that ends without a
    `stage_message` re-runs with a reminder, counted against `max_rework`,
    and parks for the user at the limit. Agree which severities count.

  Restrict the reviewers' tools to read-only where the CLI allows it (pi:
  `--tools read,bash`; that still lets bash write). A running loop picks up
  `[stages]` changes only after a restart, and stages that already started
  keep their model.
- **Hooks:** `[hooks]` lists skills the loop runs around work stages: `before`
  and `after` once per order, `before_each` and `after_each` around every work
  stage (`after_each` after its last attempt). The template writes
  `after = ["reflect"]`, which is also what noodle uses when `after` is unset;
  writing it keeps reflect visible in the config. `after = []` turns reflect
  off. Hooks are added at promotion to orders that have not started, never
  park, are skipped when they fail and record no verdict. Ask whether the user
  wants anything besides reflect.
- **How the user reviews:** ask how they want `/noodle-review` to brief them.
  Is there a doc or runbook to follow (they may point at one, or describe it in
  chat)? What do they want to see for an order: tickets, PRs, diffs, run logs,
  traces, reports, screenshots? For each, where it lives and how to open it.
  Write the answers to `brain/codebase/reviewing.md` and add it to the index;
  copy what a linked doc says rather than linking to it when the reviewer may
  not be able to read it.
- **MCP servers:** list inherited server names without secrets; ask which to keep.
  Copy kept definitions to `brain/agent-mcp.json`, mode 600, and use strict
  config even if empty. Some servers write their own state into the checkout (a
  local database directory, for example); exclude it in Step 4d. Test with
  `claude -p --strict-mcp-config --mcp-config <file> "list your MCP servers"`
  after the user confirms access.
- **Worktree links:** untracked setup is missing in cooks' worktrees unless
  linked: `[worktree] link = ["brain", "adapters", ".noodle.toml", ".agents"]`
  plus approved paths (shared dependency directories and credential files,
  below). Claude needs `--add-dir <absolute repo>/brain` to write through the
  brain link; grant the narrowest directory.
- **Review diffs:** `[worktree] diff_against_local_only = true` makes the UI's
  review diff compare a cook's branch with the local default branch instead of
  `origin/<default>`. Keep it on when `origin` can lag the local branch (for
  example `origin` is a personal fork and the default branch tracks another
  remote); otherwise a cook that made no commits shows every commit `origin`
  is missing. The upstream behaviour is `false`. Check `git remote -v` and the
  default branch's upstream (`git rev-parse --abbrev-ref main@{upstream}`)
  before choosing.
- **Dependencies:** ask whether worktrees share installed dependencies or install
  their own. Inventory root and workspace `node_modules` (actual directories).
  With shared dirs, cooks never install, update or write `node_modules`; the user
  installs once in the root and refreshes after pulls. With separate dirs, agree
  the allowed install command.
- **Credentials:** ask which untracked files verification needs, where they come
  from, when they expire and how to refresh them. Ask whether cooks may read each
  one; they never print, copy or commit it. Add approved paths to
  `worktree.link` (cooks never create their own links) and `--add-dir` their
  narrowest directory, saying that it exposes the whole directory. Check presence
  without printing contents. Record how long each token lasts. Do not run
  refresh or login unasked.

For Claude, keep every argument in the one `[agents.claude]` table, with
`--disallowedTools` last (it consumes a list), and add an
`"--add-dir", "<approved directory>"` pair before it for each credential or
data directory the user approved. Replace every placeholder. Do not pass Claude flags to
Codex; check its help for equivalents. The denials block blanket staging, also
inside `&&` chains, but not `git add *`, so the skill rules in Step 4b still
matter. The dispatcher requests `--permission-mode bypassPermissions`; do not
infer effective permissions from arguments, use `/noodle-feed` Step 8.

## Step 4: Ship the loop skills

Skills come from two places, searched in `skills.paths` order, first match
wins:

1. `$TARGET/.agents/skills/`: copies of noodle's skills from
   `$NOD/.agents/skills/`, pinned per project.
2. `$USER_SKILLS`: the user's own skills, read live. An edit there reaches the
   next cook in every project that lists it. Claude cooks read them through
   the `--add-dir <absolute $AGENTS>` grant (skill links point into
   `$AGENTS/commands/`, so grant `$AGENTS`, not only `$USER_SKILLS`).

List both sets (`ls "$NOD/.agents/skills" "$USER_SKILLS"`) next to the skills
the Step 2b pipeline names, and mark names present in both. Default copy set:
`adversarial-review`, `brain`, `commit`, `execute`, `meditate`, `oops`, `plan`,
`quality`, `refine`, `reflect`, `ruminate`, `schedule`, `todo`, `testing`,
`worktree`, `noodle`, plus any other noodle skill the pipeline names. Ask, per
name present in both, which one the cooks use:

- **Noodle's:** copy it into `.agents/skills/`; it shadows the user's.
- **The user's (substitute):** do not copy it; the user's resolves. If an
  earlier init copied it, remove the copy only after the user agrees.

A substitute for a loop skill must keep noodle's contract, or the loop breaks
quietly. Before agreeing, read the user's skill and say which of these it
lacks: `schedule` (frontmatter `schedule:` field, writes
`.noodle/orders-next.json`), `execute` (`stage_yield`, `NO CHANGE NEEDED:` and
`UNVERIFIED:` outcomes), `quality` and any stage with a `reject` action (ends
with a `stage_message`, blocking on reject), `reflect` (`stage_yield`), `todo`
(the `brain/todos.md` format the adapters parse). Skills used only as stages
or hooks need just the `stage_message` rule when they decide accept or reject.

`publish_action = "draft-pr"` always runs noodle's builtin publish code, never
a skill of that name; the user's `draft-pr` skill is unused as a publish
action.

Copies, not symlinks, for `.agents/skills`: a source change must not silently
change a project's loop, and a Claude reviewer cannot follow a link out of its
allowed directories. The user's skills are the deliberate exception. On a
resync, `diff -rq "$NOD/.agents/skills" "$TARGET/.agents/skills"`, show each
difference and copy only with approval. The source skills already carry the
generic rules: staging by explicit path (`commit`, `worktree`); running every
command in `brain/principles/verification.md`, judging no-change results and
rejecting off-limits paths (`quality`); the no-change and unverified outcomes
(`execute`); the `stage_yield` step (`reflect`); ticket-key order titles
(`schedule`).

Interview verification, then write the note (read an existing one first and ask
only what changed):

- Exact test, lint/format and typecheck commands, the runtime command for
  changed behavior, and what does not count.
- Target, case, repeat count and pass bar. Do not impose 5/5 on a flaky case
  without agreement. A deployed environment runs main, so it cannot prove a
  worktree's change; it serves as a baseline. A "no change needed" claim needs a
  run on the code the ticket was filed against (the deployed baseline) as well
  as a local one.
- Shared resources: does verification share an account or service whose state
  matters? If not, runs may go in parallel. If it does, record two parts. In
  the project's setup guide (cooks do not read it): the bootstrap the user runs
  once per loop session (services to start, data to seed) with the exact
  commands. In the verification note: only the read-only check a cook runs
  first, its UNVERIFIED label for a failed check, and that cooks never start,
  stop, seed or reconfigure the resource. Also say whether runs must be
  serialized. Init records both; it never runs a seed or other write to the
  shared resource.
- Service map: when verification uses services (a harness, a cache, a backing
  API, a deployed baseline), write `brain/codebase/local-services.md` and add it
  to `brain/index.md`: one table of service, where it runs (local or which
  environment, host and port) and what uses it; what that means for a result
  (which cases are only meaningful against which target); and what a cook does
  when one is down (the verification note's UNVERIFIED rule). No start, seed or
  setup commands: cooks read the index, and the hands-off rule applies.
- Credentials, link targets, refresh, and service readiness (for example a
  cache or container the harness needs). Require a real readiness answer (a
  ping reply, an HTTP health check), not a live process. Ask before starting services, a harness or a paid eval.

If verifying one item takes more than two commands or temporary files, offer a
helper under `brain/scripts/` (for example one that runs a named case N times
and one that runs a command against a harness built from the checkout). It prints
`RESULT <case>: k/N passed at <sha> against <url>. Logs: <path>`, fails when its
command fails, and stops only processes it started.

Write `brain/principles/verification.md`: `# Verification`, bullets, about 30
lines, no frontmatter. Name exact commands, pass bar, target, preconditions, logs,
readiness, allowed credential reads and the blocked-change outcome. Include: wait
for commands in the foreground and never end a turn while one runs; stop only
process ids you started, never by name; credentials are linked, never copied or
printed; a build is not runtime verification; quality rejects an item whose
session lacks the required runs unless the item allows a trace-backed diagnosis.
Link the note and helpers from `brain/index.md`.

### Step 4b: Commit hygiene

Cooks commit only files they created or edited for the item, each by explicit
path (never `git add -A`, `add .`, `add *` or `commit -a`), and read
`git diff --cached --stat` before committing. The source `worktree` and `commit`
skills say so, and the `quality` skill rejects off-scope changes, binary or
generated files, and anything under `.noodle/`, `brain/`, `.worktrees/` or a
tool's own state directory. Confirm the copies match the source and the Step 3 denials are in
the config. Excluding a path does not authorize committing it.

### Step 4c: Standing permissions

Ask what every item may do without asking and write
`brain/principles/standing-permissions.md` (the `execute` skill reads it): shared
files that are fair game, a rule that commits name other agents affected by
shared prompt changes, the dependency rule from Step 3, and "never stop
processes by name". The `execute` skill already defines "No change needed"
(no commit, `stage_yield` starting `NO CHANGE NEEDED:`) and "Unverified change"
(`UNVERIFIED:` with the blocker and baseline evidence). Ask per repo whether a
diagnosis is an accepted outcome and where it is written.

### Step 4d: Root checkout state

Show `git status --short`. Tracked changes block the default merge publish;
untracked files do not, but cooks can read them. Ask per tracked change: commit,
a named stash, or an approved patch backup. Never use bare `git stash` in a
worktree (the stash stack is shared). Add agreed tool-generated directories (an
MCP server's state, for example) to info/exclude. Do not commit unasked.

## Step 5: Interview task sources

Ask for every source: trackers (CLI, MCP or API; the credential's env var name,
never its value; project key, repo or board), docs, and pasted text. Write
`brain/codebase/task-sources.md` (`# Task Sources`, bullets, under about 50 lines):

```markdown
# Task Sources

- Tracker: <name>
- Method: <CLI, MCP or API command shape>
- Credential: token in $<ENV_VAR>, never the value
- Scope: <project key, repo or board>
- Verified: <date> - <command that worked>

Docs:
- <path or URL> - <contents>

Pasted text: <yes/no and habit>
```

Mark a method verified only after it worked. Tracker access belongs to the
user's feed and review sessions, not to cooks. Cooks write proposed comments to
`brain/<tracker>/<item>.md`; no Done line may require posting to an external
system. Ask which datasets, rubrics and shared prompts items may edit. Link the
note from `brain/index.md`.

## Step 6: Walk the known traps

Go through each item with the user, say whether it applies here, and record
what was decided in the matching brain note and its index line. Ask only about
the ones that apply.

- Permission mode: the user's settings can downgrade cooks from
  `bypassPermissions`, and the classifier may then block their commands
  (the first-cook check in `/noodle-feed` Step 8 shows it).
- Writes outside the repo: cooks cannot finish work that needs them (tracker
  comments, cleanup elsewhere). Design items around it: tracker text goes to
  `brain/<tracker>/<item>.md`.
- Credentials: linked into worktrees and granted with `--add-dir`, never copied
  or printed; record how long each lasts and how the user refreshes it.
- Long commands: cooks wait in the foreground and never end a turn while one
  runs; a cook that does parks as "ended its turn without changes".
- Processes: stop only process ids you started, never by name; helpers can
  survive a stop with parent pid 1 in a worktree.
- Shared resources and services: bootstrap steps in the setup guide for the
  user, the check and UNVERIFIED label in the verification note, the service
  map in `brain/codebase/local-services.md` (Step 4).
- Deployed baseline: a deployed environment runs main, so it can only be a
  baseline; a "no change needed" claim needs both runs, except where the
  baseline cannot see the same data.
- Repo state: noodle edits the tracked `.gitignore` when it creates the first
  worktree; tracked changes in the root checkout block merges.
- Adapters: `bash -n` after every edit; a syntax error stops the loop.
- Loop state: a loop runs only if a `noodle start` process exists, whatever
  `.noodle/status.json` says; restart only with no cook running; never
  `noodle start --once` with orders queued.
- Scheduling: ordering lines between items keep the scheduler to one order; a
  Reject reads as bad work, so say "cancelled" when that is meant.
- Reviewer CLI: `adversarial-review` shells out to another model's CLI; when
  that CLI is missing or signed out the review can come back thin or empty.
  Wrap it with `[stages.adversarial-review] system_prompt` and smoke-test the
  command (Step 3).
- Verdicts: a `[stages.<task>] reject` action only fires on a failed cook or a
  blocking `stage_message`; check the skill, or its `system_prompt`, emits one.

## Step 6b: Verify

Run `noodle skills list` and check that every skill `brain/principles/pipeline.md`
names resolves from the source agreed in Step 4 (copy or the user's), and, if supported,
`noodle schema mise >/dev/null` as a schema check (not config validation). Check
adapter executability and paths, `diff -rq` of the skills, config arguments and
links, credential permissions without values, dependency versions and service
readiness. Show commands and results; never describe a skipped check as passed.
With permission, test a helper case from a worktree, including a failing
command, and confirm the RESULT line's SHA and target, the exit status, and that
no listeners are left. Never use `noodle start --once`: queued orders can spawn
cooks and leave them orphaned and unlogged.

## Step 7: Report

One line each: binary and source commit and capability gaps; the pipeline kinds
and their stages; skills copied, skills substituted by the user's and any
contract gaps found; adapters and todos path; model, concurrency and
scheduler policy; delivery and `[review]` values; `[stages.<task>]` actions,
harness/model and whether a `system_prompt` wraps the skill, with the reviewer
CLI's auth and smoke-test result; `[hooks]` values; MCP servers and directory
grants; credentials and readiness prerequisites; verification note, helpers and
results; standing-permission and model-routing notes; root changes left; index
links.

Then explain how the loop is driven:
- External holds wait until `/noodle-review` resolves them; the loop looks
  stalled otherwise. `/noodle-review` also sends `approve-and-publish` for an
  order awaiting publish.
- A parked stage takes a verdict with
  `noodle order <id> resolve <stage> <accept|reject> <action> [--feedback-file <f>]`;
  the feedback reaches every later stage's prompt. Stages with a configured
  `[stages.<task>]` action move on by themselves.
- In the UI, a gated order's parked stage offers "Continue to <next stage>"
  (plain "Approve" at the last stage); Approve & Publish appears only when the
  order awaits publish; every action button shows a spinner until the loop
  acknowledges it and then the result next to it (guide §3.4 "What the UI
  shows"). After any decision, re-read the queue to confirm the effect.
- Dismissing or cancelling an order is recorded as a rejection, and the
  scheduler may stop scheduling until told why.

Point out known limits without diagnosing them: a scheduler process can stay
alive after finishing; noodle edits the tracked `.gitignore` when it creates the
first worktree; a cook that ends its turn with a command running parks as
"ended its turn without changes". Do not restart or rebuild a running binary
without permission.

Check that the commands are discoverable in the user's harness. If stow links
are missing, read the Makefile before proposing a command (`make stow` can update
submodules). Next is `/noodle-feed`. Init never starts the loop.
