# dotfiles - agent rules

This is the dotfiles repo. Two things an agent working here needs:

- **Behavioral rules** (how to act, commit style, tone): `SYSTEM_PROMPT.md`.
  This is the shared system prompt the harnesses load (`.claude/CLAUDE.md`,
  `.pi/agent/AGENTS.md`, and `.config/maki/AGENTS.md` all symlink to it).
- **Repo layout** (submodules, vendored plugins, the `~/.config` symlink map,
  the `~/.maki` runtime dir, git gates): `STRUCTURE.md`.

Read `STRUCTURE.md` before any structural change (moving dirs, editing a
submodule, touching `~/.maki` or `~/.config`). Per-harness notes live in
`docs/harnesses/`.

## Tests and lint before you change things

- **Write/run tests *before* a restructure, not after.** If a change moves
  code across a boundary (e.g. splitting a function into a wrapper + impl),
  first add a test that pins the current behavior, confirm it passes, *then*
  make the change. This catches regressions while the original is still the
  source of truth.
- **Run the existing suite before you start editing** so any later failure is
  clearly yours, not pre-existing.
- **Lint and tests must pass before pushing.**
  - `make lint` - runs `lint-python` (ruff, config in `ruff.toml`) +
    `lint-shell` (shellcheck, scoped to `.config/tmux/scripts/`).
  - `make lint-fix` - ruff auto-fixer for mechanical findings (import sort,
    unused imports). Run before commit: `make lint-fix && make lint`.
  - `make test` - the zsh tests (docker), the tmux picker tests, and
    `test-agent-links` (harness skill/command links resolve).
  - The Neovim config lints itself separately: `make -C .config/nvim ci`.
- **Intentional lint exceptions get an inline `# noqa` with a concise reason**
  (not a blanket config ignore), so the reason lives at the site and survives
  refactors. E.g. the picker's "resolve with a safe fallback" idiom uses
  `# noqa: BLE001 - <why>` on each blind-except. If a new one appears without a
  reason, ruff flags it - that's the point.

## Adding a command

`agents/` is the source of truth for skills and commands; every harness dir
links into it (`.claude/skills`, `.copilot/skills`, `.pi/agent/skills`,
`.pig/agent/skills` -> `agents/skills`; `.claude/commands` and
`.{pi,pig}/agent/prompts` -> `agents/commands`). Add files under `agents/`,
never under a harness dir. Map: `STRUCTURE.md`.

Every user-invocable command in `agents/commands/<name>.md` also exists as a
skill so the model can trigger it by description, not just via the slash name:
create `agents/skills/<name>/SKILL.md` as a symlink to
`../../commands/<name>.md`. One source of truth, two entry points. An alias is
another dir with the same symlink (e.g. `agents/skills/try/SKILL.md ->
../../commands/watch-tests.md`). Vendored-plugin commands
are exposed as skill symlinks in `agents/skills/` (see `Vendored plugins`),
not as command files here.

## Vendored plugins

External skill repos are vendored as submodules and exposed via symlinks in
`agents/skills/`: ponytail stays in `.claude/plugins/` (see
`.claude/plugins/AGENTS.md`), noodle lives in `agents/tools/` (see
`agents/tools/AGENTS.md`). Submodule mechanics: `STRUCTURE.md`. Read the
relevant AGENTS.md before adding, removing, or relinking any plugin skill.
