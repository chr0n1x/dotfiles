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
  - `make test` - the zsh tests (docker).
  - The Neovim config lints itself separately: `make -C .config/nvim ci`.
- **Intentional lint exceptions get an inline `# noqa` with a concise reason**
  (not a blanket config ignore), so the reason lives at the site and survives
  refactors. E.g. the picker's "resolve with a safe fallback" idiom uses
  `# noqa: BLE001 - <why>` on each blind-except. If a new one appears without a
  reason, ruff flags it - that's the point.

## Adding a command

Every user-invocable command in `.claude/commands/<name>.md` also exists as a
skill so the model can trigger it by description, not just via the slash name:
create `.claude/skills/<name>/SKILL.md` as a symlink to
`../../commands/<name>.md`. One source of truth, two entry points. Plugin
commands that are not meant to be triggered (e.g. `watch-tests`) have
no skill entry. Vendored-plugin commands are exposed as skill symlinks in
`.claude/skills/` (see `Vendored plugins` and `.claude/plugins/AGENTS.md`),
not as command files here.

## Vendored plugins

External skill repos are vendored as submodules under `.claude/plugins/` and
exposed via symlinks in `.claude/skills/` (scanned by maki and Claude Code).
Submodule mechanics: `STRUCTURE.md`. What is linked, what was skipped, and
why: `.claude/plugins/AGENTS.md` - read it before adding, removing, or
relinking any plugin skill.
