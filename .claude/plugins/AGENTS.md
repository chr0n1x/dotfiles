# .claude/plugins - vendored agent skills (ponytail)

Vendored skill repos that stay under `.claude/plugins/`. Each skill is
exposed via a symlink in the shared skills dir `agents/skills/`:
`agents/skills/<name> -> ../../.claude/plugins/<repo>/<skill-dir>` (relative
to `agents/skills/`). Verify with
`readlink -f agents/skills/<name>/SKILL.md` from the repo root. Other vendored
tools (noodle) live in `agents/tools/` - see `agents/tools/AGENTS.md`.
Layout and submodule mechanics: `../../STRUCTURE.md`.

## ponytail

Repo: `https://github.com/DietrichGebert/ponytail` (lazy senior-dev mode).
All 6 skills linked. Only the `ponytail` skill is also exposed as a command
(`agents/commands/ponytail.md -> ../skills/ponytail/SKILL.md`): it is the
persistent mode, the one meant to be invoked as `/ponytail [level]`. The
other 5 (`audit`, `debt`, `gain`, `help`, `review`) are one-shot skills that
carry their own `/ponytail-*` triggers in their descriptions and need no
command entry. The repo's own 6 `.toml` command files are not linked -
`.toml` is not this repo's command format and the skill symlinks cover the
commands. Bump with
`git submodule update --remote .claude/plugins/ponytail`.
