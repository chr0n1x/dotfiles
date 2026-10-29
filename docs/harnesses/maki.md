# maki

Operational notes for the maki harness as it runs inside this dotfiles setup.
Referenced from `STRUCTURE.md`. Other harnesses get their own file here
(`docs/harnesses/<name>.md`) as notes accumulate.

## `~/.maki`: runtime state, not config

`~/.maki` is a **real dir** (not a symlink). It holds maki's runtime state:
`sessions/`, `projects/`, `maki.log`, locks, model caches. Do not commit or
edit it as config.

`~/.config/maki` (a symlink into the repo) is the *config*. The two are
separate: config in `~/.config/maki`, state in `~/.maki`.

Two `~/.maki` entries are symlinks back into the repo config (machine-specific
overrides that should track the repo):
```
~/.maki/permissions.toml -> ~/Code/$USER/dotfiles/.config/maki/permissions.toml
~/.maki/theme            -> ~/Code/$USER/dotfiles/.config/maki/theme
```
The other `~/.maki` files (`providers.toml`, `model`, `sessions/`, etc.) are
local and stay local.

## Log file gotcha

maki does **not** always log to `~/.local/logs/maki/maki.log`. An instance may
write to `~/.maki/maki.log` instead. Before grepping, find the real path from
the running process:
```
ls -l /proc/<maki-pid>/fd | grep maki.log
```
Grep the file that shows up, not the obvious one.

## Config loading

maki searches for `init.lua` in `~/.maki` first, then `~/.config/maki`, and
**stops at the first that exists**. `~/.maki` has no `init.lua`, so the one in
`~/.config/maki` (the repo) loads. Subdirectories of the config dir are not
discovered; `init.lua` must `require` them explicitly.

`require` in a config `init.lua` resolves under `<config dir>/lua/`, so
`require("smooth_scroll")` loads `<config dir>/lua/smooth_scroll.lua`. It is a
custom sandboxed loader, not stock Lua `require`: `io`, `package`, and stock
`require` are nulled before the chunk runs, and `dofile` is unavailable.

`maki.env.config_dir()` collapses to `~/.maki` whenever that dir exists, so do
not use it to locate files under `~/.config/maki`. Use `require` instead.

## Path references

When feeding a file into maki (via the nvim harness `<leader>ca` / `<C-t>`, or
by hand), the path must be resolvable by maki's `read` tool, which takes
`offset`/`limit`. The path itself must be absolute-ish (`shorten_path`: ~-collapse
under `$HOME`, else full path) so it resolves regardless of where the session's
cwd is. A line range is a hint for the model, not machine-parsed: use
`path#L<start>-<end>` for a hunk and `path#L<n>` for a single line. Omit the
suffix when referring to the whole file.

## question tool debugging

The `question` tool renders predefined options as a cursor-navigable
list; with no `options` in the payload it degrades to a plain text box.
The `gate` plugin (`.config/maki/lua/gate.lua`) wraps it with a flat
three-string input for yes/no confirmations.

Debugging a question prompt that renders as a text box: the payload is
missing `options`. Verify against the raw input in
`~/.maki/sessions/*.jsonl` - search `"name":"question"` and check the
parsed JSON for an `options` key. A substring match is not enough; the
word "options" appears in headers and descriptions.
