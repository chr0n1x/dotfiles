---
name: show
description: Open a file and jump to the line where something is defined or happens in the user's running Neovim instance. Use when the user asks "show me where X happens", "where is X defined?", "where do we define Y?", "show me the code for Z", or anything asking to locate and reveal a symbol, function, config, or behavior in the editor.
user-invocable: true
argument-hint: "[what to show, e.g. \"the auth middleware\", \"where we define TaskRunner\", \"where the config gets loaded\"]"
allowed-tools: Bash(nvim:*), Bash(echo:*), Grep, Glob, Read, index, skill
---

# Show

Open the file in the user's Neovim and jump to the line where the thing they asked about is defined or happens.

## Step 1: Check for Neovim

```bash
echo "$NVIM"
```

If empty, stop and tell the user: "I'm not running inside a Neovim terminal, so I can't open anything in your editor. Run me from a terminal inside Neovim to use `show`." Do not attempt any nvim RPC.

## Step 2: Find it

Use the argument (or the user's question) to locate the definition. Prefer an exact definition over a call site. Typical approach:

- `Grep` for the symbol (e.g. `fn <name>`, `def <name>`, `function <name>`, `<name>(`, struct/class/interface/type declarations, or the config key).
- If multiple candidates, pick the definition, not usages. If it is genuinely ambiguous (two definitions in different modules), open the one matching the user's context and say where the other one is.

Record the absolute file path and the 1-indexed line number.

## Step 3: Open it in the user's Neovim

Follow the `nvim-ctrl` skill (command-substitution + `grep -v` pattern to suppress the `NVIM_APPNAME` warning):

```bash
result=$(nvim --server "$NVIM" --remote-expr "execute(\"edit! <ABS_PATH>|call cursor(<LINE>)|normal! zz\")") && echo "$result" | grep -v '^Warning: Using NVIM_APPNAME='
```

Use `edit!` so the buffer is opened even if it is already open, and `normal! zz` to center the definition in the window.

## Step 4: Report

One line: what was opened and where, e.g. "Opened `src/auth/middleware.go:42` - that is where `AuthMiddleware` is defined." If there are other relevant locations, list them briefly.
