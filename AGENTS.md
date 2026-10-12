# dotfiles - agent rules

This is the dotfiles repo. Two things an agent working here needs:

- **Behavioral rules** (how to act, commit style, tone): `SYSTEM_PROMPT.md`.
  This is the shared system prompt the harnesses load (`.claude/CLAUDE.md`,
  `.pi/agent/AGENTS.md`, and `.config/maki/AGENTS.md` all symlink to it).
- **Repo layout** (the two-repo/submodule split, the `~/.config` symlink map,
  the `~/.maki` runtime dir, and the confirmation gates for git): `STRUCTURE.md`.

Read `STRUCTURE.md` before any structural change (moving dirs, editing a
submodule, touching `~/.maki` or `~/.config`). Per-harness notes live in
`docs/harnesses/`.

## Adding a command

Every user-invocable command in `.claude/commands/<name>.md` also exists as a
skill so the model can trigger it by description, not just via the slash name:
create `.claude/skills/<name>/SKILL.md` as a symlink to
`../../commands/<name>.md`. One source of truth, two entry points. Plugin
commands (the ponytail `.toml` set, loaded via the plugins dir) and reference
commands that are not meant to be triggered (e.g. `watch-tests`) have
no skill entry.
