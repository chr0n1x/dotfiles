---
name: show
description: Open a file in the user's running Neovim instance, optionally
  jumping to a specific line. Use when the user says "show me X", "open X",
  "where is X defined?", "show me where X happens", or asks to reveal a
  symbol, file, config, or code location in their editor. Handles both
  "find and open" (search for the definition first) and "just open"
  (the referent is already known from context).
user-invocable: true
argument-hint: "[what to show, e.g. \"the auth middleware\",
  \"where we define TaskRunner\", \"where the config gets loaded\"]"
allowed-tools: Bash(nvim:*), Bash(echo:*), Grep, Glob, Read, index, skill
---

# Show

Open a file in the user's Neovim. When a line is known, place the cursor on
that line and verify its position before reporting success.
Two modes:

- **Find and open**: the user asks "where is X defined?" or "show me where
  X happens." Search for it, then open.
- **Just open**: the user says "show me that file" or "open the config" and
  the referent is already known from conversation context. Open it directly.

## Step 1: Check for Neovim

```bash
echo "$NVIM"
```

If empty, stop and tell the user: "I'm not running inside a Neovim terminal,
so I can't open anything in your editor. Run me from a terminal inside
Neovim to use `show`." Do not attempt any nvim RPC.

## Step 2: Resolve the target

**Just open** (referent known from context): use the file path directly. If
a line number is also known, use it. If no line number, open the file at the
top.

**Find and open** (referent is a symbol, concept, or vague description): use
the argument to locate the definition. Prefer an exact definition over a
call site. Typical approach:

- Use the `grep` tool (not raw `grep` in bash) to search for the symbol
  (e.g. `fn <name>`, `def <name>`, `function <name>`, `<name>(`,
  struct/class/interface/type declarations, or the config key).
- If multiple candidates, pick the definition, not usages. If it is
  genuinely ambiguous (two definitions in different modules), open the one
  matching the user's context and say where the other one is.

Record the absolute file path and the 1-indexed line number (or omit the
line if just opening a file).

## Step 3: Open it in the user's Neovim

Follow the `nvim-ctrl` skill (command-substitution + `grep -v` pattern to
suppress the `NVIM_APPNAME` warning):

**With a line number:** Open the file in a tab, then set the cursor in the
window displaying that buffer. A `--remote-expr` sent from a Neovim terminal
can run in the terminal's window; `edit! ...|normal! zz` can fail with
`Can't re-enter normal mode from terminal mode`. Do not fall back to merely
opening the file when a line is known.

```bash
nvim --server "$NVIM" --remote-tab <ABS_PATH>
result=$(nvim --server "$NVIM" --remote-expr \
  'luaeval("(function() local path = \"<ABS_PATH>\"; for _,b in ipairs(vim.api.nvim_list_bufs()) do if vim.api.nvim_buf_get_name(b) == path then for _,w in ipairs(vim.fn.win_findbuf(b)) do vim.api.nvim_win_set_cursor(w, {<LINE>, 0}); return vim.json.encode({path=path, line=vim.api.nvim_win_get_cursor(w)[1]}) end end end return \"buffer not visible\" end)()")') \
  && printf '%s\n' "$result" | grep -v '^Warning: Using NVIM_APPNAME='
```

Verify the result reports the requested path and line. If it reports `buffer
not visible` or a different line, say the jump failed instead of claiming it
worked. Use absolute paths without quotes or backslashes in the placeholder;
otherwise escape them for the nested Lua string.

**Without a line number (just open the file):**

```bash
result=$(nvim --server "$NVIM" --remote-expr \
  "execute(\"edit! <ABS_PATH>\")") \
  && echo "$result" | grep -v '^Warning: Using NVIM_APPNAME='
```

For a file without a known line, `edit!` opens the buffer even if it is
already open. Use `execute()` rather than `vim.cmd()` for that RPC command:
`vim.cmd()` via `--remote-expr` can hang waiting for a response.

## Step 4: Report

One line: what was opened and where, e.g. "Opened
`src/auth/middleware.go:42` - that is where `AuthMiddleware` is defined."
If there are other relevant locations, list them briefly.
