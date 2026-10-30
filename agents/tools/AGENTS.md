# agents/tools - vendored agent tooling

Vendored tool repos (submodules) whose skills are exposed through
`agents/skills/`. Layout and submodule mechanics: `../../STRUCTURE.md`.

## noodle


Repo: `https://github.com/poteto/noodle` (Go agent-orchestration framework).
Added 2026-10-25. Framework NOT installed: no binary, no `.noodle.toml`, no
`adapters/`. Of the repo's 29 skills, 3 are linked into `agents/skills/`
(`agents/skills/<name> -> ../tools/noodle/.agents/skills/<name>`):

| linked | note |
|---|---|
| `ast-grep` | the `ast-grep` binary is NOT installed; skills reference it conditionally, rg fallback |
| `debugging` | root-cause methodology |
| `unslop` | strip AI-speak from prose; also exposed as a command file (`agents/commands/unslop.md -> ../tools/noodle/.agents/skills/unslop/SKILL.md`) |

`review` was linked and exposed as a command file, then removed: it
collided with this repo's own `review` skill (house style, same trigger
phrases). Remains available in the submodule if wanted back.

The loop playbook (the remaining 16 skills) is not linked here - it is
shipped per-project by the `noodle-init` command
(`agents/commands/noodle-init.md`), which copies them from this submodule
into each Noodle project's `.agents/skills/`. Companions: `noodle-feed`
(epic -> refined `brain/todos.md` items) and `noodle-distill` (general
learnings from the project's gitignored `brain/` -> the user's global
Obsidian vault via the `obsidian-*` skills). All three follow the normal
command+skill-symlink convention. The project `brain/` vault is personal and
untracked by design; `/noodle-distill` is what promotes durable bits out of
it.

Cross-references: `analyze` (step 3: grep finds regions, ast-grep confirms
shapes) and `watch-tests` (step 4: `debugging` for non-obvious failures,
ast-grep for structural ones).

Not linked, and why:
- `commit`, `worktree`, `review` - collide with this repo's `commit-push`,
  `worktree`, and `review` skills; noodle's worktree skill is entirely
  `noodle worktree` CLI, dead without the binary; noodle's `review` was
  linked then removed on trigger collision with the house `review` skill
- loop pipeline (`noodle`, `schedule`, `execute`, `plan`, `quality`,
  `testing`, `todo`, `oops`, `adversarial-review`, `refine`) and brain
  cluster (`brain`, `reflect`, `meditate`, `ruminate`) - inert without the
  binary and the `brain/` vault
- meta (`codex` needs the codex CLI; `find-skills`, `skill-creator`)
- domain best-practices (`frontend-design`, `interaction-design`,
  `make-interfaces-feel-better`, `go/react/ts-best-practices`) - not relevant
  to this stack (zsh/lua/python) yet
