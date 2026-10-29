# STRUCTURE

Operational map of `~/Code/$USER/dotfiles` and how it wires into the home dir.
Read this before making structural changes (moving dirs, editing submodules,
touching `~/.maki` or `~/.config`). Not an architecture doc: no design rationale.

## Two repos, one working dir

The dotfiles root is a git repo. `.config/nvim` is a **submodule** pointing at a
separate repo (`chr0n1x/neovim-configs`). They have independent git state.

- `git status` at the root shows the submodule as one opaque line: `M .config/nvim`.
  That hides how many files actually changed inside it. Always run
  `git -C .config/nvim status` to see the real picture.
- Other submodules: `.tmux/plugins/tpm` (tmux plugin manager) and
  `.claude/plugins/{ponytail,noodle}` (vendored agent-skill repos -
  `.claude/plugins/AGENTS.md` records what is exposed and why). Same rule.

## Submodules: the harness knows, the agent does not act

This repo has several submodules (`.config/nvim`, `.tmux/plugins/tpm`,
`.claude/plugins/ponytail`). The harness is expected to understand that layout:
each submodule is its own git repo with its own remote, and a change inside one
is not visible to a fresh clone of the dotfiles root until the pointer in the
root is bumped and both are pushed (submodule first, then the root, so the
pointer the root records already exists on the submodule remote).

Knowing that is not the same as doing it. **Do not bump a submodule pointer,
commit the dotfiles root, or push either repo without explicit confirmation
from the user.** The default after editing inside a submodule is to stop,
report what changed and that a pointer bump would be needed, and wait.

## Symlink map

`~/.config/<app>` is a **directory symlink** into the repo for each managed
app. The repo holds the real files; the home dir holds the link.

```
~/.config/crush    -> ~/Code/$USER/dotfiles/.config/crush
~/.config/maki     -> ~/Code/$USER/dotfiles/.config/maki
~/.config/nvim     -> ~/Code/$USER/dotfiles/.config/nvim   (submodule)
~/.config/tmux     -> ~/Code/$USER/dotfiles/.config/tmux
~/.config/waybar   -> ~/Code/$USER/dotfiles/.config/waybar
~/.config/zsh      -> ~/Code/$USER/dotfiles/.config/zsh
```

Consequences:
- `ls -la` on a file *inside* a symlinked dir shows the target's real-file mode.
  Do not misread that as a second copy. There is one copy; it is the repo file.
- Editing `~/.config/nvim/foo.lua` edits the repo file. No sync step needed.
- `readlink -f` resolves any of these to the repo path. Three spellings, one file.

## Harness notes

Per-harness operational notes live in `docs/harnesses/`. maki: see
[`docs/harnesses/maki.md`](docs/harnesses/maki.md) (`~/.maki` runtime state vs.
`~/.config/maki` config, the log-file location gotcha, and how `init.lua` /
`require` load). Other harnesses get a file here as notes accumulate.

## Pre-existing uncommitted work

A submodule can carry uncommitted changes from a previous session. At the dotfiles
root they appear as a single `M .config/nvim` line. Do not assume the diff is only
what you just did. Inspect inside the submodule (`git -C .config/nvim status` /
`diff`), report what is new vs. leftover, and **do not stage, commit, or push
without explicit confirmation from the user.**
