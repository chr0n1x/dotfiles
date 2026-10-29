---
name: noodle-init
description: Set up Noodle (skill-based agent orchestration) for a project -
  scaffolds .noodle/, .noodle.toml, the brain vault, backlog adapters, and the
  loop skills from the vendored submodule. Use when the user says "init noodle",
  "set up noodle", "start a noodle project", or asks to run noodle in this repo.
user-invocable: true
argument-hint: "[target repo path, default: pwd]"
---

# Noodle Init

Set up Noodle for one project. The vendored checkout at `~/.claude/plugins/noodle`
(NOD) is the source for skills and adapters: copy them, never hand-patch the
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

Use the repository root as TARGET. Set `NOD=~/.claude/plugins/noodle` and check
`$NOD/.agents/skills/schedule/SKILL.md` exists; if not, ask for the dotfiles repo
path. Do not initialize or update a submodule without permission.

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
`noodle review --help`, and the `[review]` keys in `$NOD/config/fork.go`, for the
features the user needs (external holds, `noodle order <id> complete <stage>`,
`approve-and-publish`, `auto_verify_quality`, worktree links). This command was
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
paths = [".agents/skills"]

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
external_stages = ["adversarial-review"]
extra_stages = ["adversarial-review", "reflect"]
publish_action = "draft-pr"
```

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
  order is published. The recommended gated setup:

  ```toml
  [review]
  auto_verify_quality = true
  external_stages = ["adversarial-review"]
  extra_stages = ["adversarial-review", "reflect"]
  max_rework = 2
  publish_action = "draft-pr"
  ```

  What each key does (verify against `config/fork.go`):
  - `auto_verify_quality`: after each execute succeeds the loop inserts a
    `quality` stage run as its own cook; a blocking reject sends execute back as
    rework. Only in gated configs; default false.
  - `external_stages`: stages held with no agent until
    `noodle order <id> complete <stage> --file <review.md> [--reject]`; the stage
    name must be the held task key. Accept never publishes. `[]` for none.
  - `extra_stages`: skills added to every order after its quality stage, in list
    order, when the order is promoted; existing names are not duplicated and
    unknown names are skipped. Orders already promoted are not changed.
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

Copy these 16 whole directories from `$NOD/.agents/skills/` into
`$TARGET/.agents/skills/`: `adversarial-review`, `brain`, `commit`, `execute`,
`meditate`, `oops`, `plan`, `quality`, `refine`, `reflect`, `ruminate`,
`schedule`, `todo`, `testing`, `worktree`, `noodle`.

Copies, not symlinks: a source change must not silently change a project's loop,
and a Claude reviewer cannot follow a link out of its allowed directories. On a
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

## Step 6b: Verify

Run `noodle skills list` (all 16 present) and, if supported,
`noodle schema mise >/dev/null` as a schema check (not config validation). Check
adapter executability and paths, `diff -rq` of the skills, config arguments and
links, credential permissions without values, dependency versions and service
readiness. Show commands and results; never describe a skipped check as passed.
With permission, test a helper case from a worktree, including a failing
command, and confirm the RESULT line's SHA and target, the exit status, and that
no listeners are left. Never use `noodle start --once`: queued orders can spawn
cooks and leave them orphaned and unlogged.

## Step 7: Report

One line each: binary and source commit and capability gaps; skills and any
difference from the source; adapters and todos path; model, concurrency and
scheduler policy; delivery and `[review]` values; MCP servers and directory
grants; credentials and readiness prerequisites; verification note, helpers and
results; standing-permission and model-routing notes; root changes left; index
links.

Then explain how the loop is driven:
- External holds wait until `/noodle-review` resolves them; the loop looks
  stalled otherwise. `/noodle-review` also sends `approve-and-publish` for an
  order awaiting publish.
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
