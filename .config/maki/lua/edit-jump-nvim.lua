-- edit-jump-nvim: when maki writes a file, fire User HarnessEdit in the parent
-- nvim so the harness's existing jump (edit-jump.lua) opens the buffer and
-- restores focus to this terminal. No-op when maki is not running inside a
-- Neovim terminal ($NVIM unset).
--
-- The autocmd data shape matches what edit-jump.lua's on_edit reads:
--   { file_path = <abs path>, starting_line = <1-indexed line or 1> }
-- starting_line is always set: edit-jump.lua early-returns when it is nil, so
-- line-less tools pass 1 (top of file) to get the same open-but-top behavior.
--
-- The command travels as a luaeval IIFE through --remote-expr: it runs in
-- nvim's main thread regardless of the current window or mode, so focus does
-- not need to be in the maki terminal. The path is interpolated as a Lua string
-- literal with backslash and quote escaped (the only chars that can appear in
-- an absolute path and also have meaning in a Lua/Vim string literal).

local WRITE_TOOLS = {
  edit = true,
  multiedit = true,
  edit_lines = true,
  insert_lines = true,
  write = true,
}

-- Read lazily in the callback, not at require time: a missing `env` permission
-- would otherwise throw at load and kill the whole module.
local function nvim_sock()
  return maki.uv.os_getenv("NVIM")
end

local function target_line(tool, input)
  if tool == "edit_lines" and input.start then
    return input.start
  end
  if tool == "insert_lines" and input.line then
    return input.line + 1
  end
  return 1
end

-- Escape for embedding in a Lua string literal (and, since the outer Vim string
-- only needs the same escapes, for the --remote-expr argument at once).
local function escape(s)
  return (s:gsub("\\", "\\\\"):gsub('"', '\\"'))
end

local function fire(path, line, sock)
  local p = escape(path)
  local expr = string.format(
    'luaeval("(function() local p = \\"%s\\"; vim.api.nvim_exec_autocmds(\\"User\\", { pattern = \\"HarnessEdit\\", data = { file_path = p, starting_line = %d } }); return 1 end)()", {})'
  , p, line)
  maki.fn.jobstart({ "nvim", "--server", sock, "--remote-expr", expr })
end

maki.api.create_autocmd("ToolDone", {
  callback = function(ev)
    local d = ev.data
    if not d then
      return
    end
    if not WRITE_TOOLS[d.tool] or d.is_error then
      return
    end
    local path = d.input and d.input.path
    if not path or path == "" then
      return
    end
    local sock = nvim_sock()
    if not sock then
      return
    end
    pcall(fire, path, target_line(d.tool, d.input), sock)
  end,
})
