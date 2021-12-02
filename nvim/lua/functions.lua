-- globally defined functions
-- invoke using -- `:lua <function>(...)`
-- note that these require plugins to have been loaded

local async = require("plenary.async")
local notify = require("notify").async

function emptyString(str)
  return str == nil or str == ''
end

function runShell(command)
  local tmpfile = '/tmp/lua_execute_tmp_file'
  local exit = os.execute(command .. ' > ' .. tmpfile .. ' 2> ' .. tmpfile .. '.err')

  local stdout_file = io.open(tmpfile)
  local stdout = stdout_file:read("*all")

  local stderr_file = io.open(tmpfile .. '.err')
  local stderr = stderr_file:read("*all")

  stdout_file:close()
  stderr_file:close()

  return exit, stdout, stderr
end

function _G.backgroundTaskAndNotify(command)
  if emptyString(command) then
    return
  end

  async.run(function()
    local exitCode, out, err = runShell(command)
    local ok = (exitCode == 0)

    local type = "debug"
    if (ok) then
      type = "info"
      notify(out, type)
    else
      type = "error"
      notify(err, type)
    end

    if (not emptyString(err)) then
      if ok then
        notify("STDERR printed out something: " .. err, "debug")
      else
        notify(out, "error")
      end
    end
  end)
end
