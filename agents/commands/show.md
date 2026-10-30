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
allowed-tools: Bash(nvim:*), Bash(sleep:*), Bash(echo:*), Grep, Glob, Read, index, skill
---

# Show

1. If `$NVIM` is empty or its socket unavailable, stop. Resolve an absolute
   path and 1-indexed line: use the known location or `grep` for the definition.
2. Load `nvim-ctrl`. Query visible windows via RPC. Reuse the window already
   displaying the file; otherwise pick an unmodified normal-file window
   (`buftype == ""`). If none exists, stop. Never open a tab, replace a
   terminal or modified buffer, use `edit!`, or edit buffer contents.
   RPC can navigate an unfocused Neovim window; do not change tmux pane
   or window focus just to show a file. If an explicit focus switch is needed,
   remember the active pane, select the target, `sleep 2` in a separate
   command, then restore the original pane after verification.
3. In a **separate command**, `sleep 2` and use RPC to set that window's
   buffer (`vim.fn.bufnr` / `vim.fn.bufadd`, then `nvim_win_set_buf`) if needed.
   Set its cursor with `nvim_win_set_cursor(win, {line, 0})` when the line is
   known. Without a line, retain the cursor if already visible; otherwise use
   line 1. Do not run `normal!` from the terminal.
4. In another command, `sleep 2`, then RPC-query the **same window** for
   its buffer path and cursor line. Report success only if they match. Report
   failures plainly. Use `nvim-ctrl`'s `--remote-expr` pattern to suppress
   `NVIM_APPNAME` warnings.

Use separate calls (not one shell command); replace the path, line and
window ID below. If an explicit pane switch was requested, run `sleep 2`
in its own call before example 1 and restore the previous pane after example 3.
The `luaeval` result should be captured before filtering `NVIM_APPNAME`
warnings (see `nvim-ctrl`).

```bash
# 1. Inspect windows. Prefer the target if already displayed.
result=$(nvim --server "$NVIM" --remote-expr 'luaeval("vim.json.encode(vim.tbl_map(function(w) local b=vim.api.nvim_win_get_buf(w); return {win=w,path=vim.api.nvim_buf_get_name(b),type=vim.bo[b].buftype,modified=vim.bo[b].modified} end,vim.api.nvim_list_wins()))")')
printf '%s\n' "$result" | grep -v '^Warning: Using NVIM_APPNAME='
```

```bash
# 2. Reuse the selected file window; do not touch a modified buffer.
sleep 2
result=$(nvim --server "$NVIM" --remote-expr 'luaeval("(function() local w=<WIN>; local path=\"<ABS_PATH>\"; local b=vim.api.nvim_win_get_buf(w); if vim.api.nvim_buf_get_name(b) ~= path then if vim.bo[b].buftype ~= \"\" or vim.bo[b].modified then return \"unsafe window\" end; local target=vim.fn.bufnr(path); if target == -1 then target=vim.fn.bufadd(path) end; vim.api.nvim_win_set_buf(w,target) end; vim.api.nvim_win_set_cursor(w,{<LINE>,0}); return \"moved\" end)()")')
printf '%s\n' "$result" | grep -v '^Warning: Using NVIM_APPNAME='
```

```bash
# 3. Verify the same window, after Neovim settles.
sleep 2
result=$(nvim --server "$NVIM" --remote-expr 'luaeval("(function() local w=<WIN>; return vim.json.encode({path=vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w)),line=vim.api.nvim_win_get_cursor(w)[1]}) end)()")')
printf '%s\n' "$result" | grep -v '^Warning: Using NVIM_APPNAME='
```

For no known line, skip `nvim_win_set_cursor` when already on the target;
otherwise use line 1. Escape quotes and backslashes in paths. Only report
success if the verified path and line match. Reply with `path:line`.
