-- /task - spawn a subagent in an isolated git worktree with a tmux
-- window. The tmux pane IS the subagent's shell: every command is
-- sent into the pane via send-keys, and output is read via
-- capture-pane. The user watches everything happen in real time.
--
-- Requires: run, env permissions (for jobstart to create the worktree
-- and tmux window). agent permission (for maki.agent.session).

local POLL_MS = 1000
local MAX_WAIT_S = 300
local CAPTURE_LINES = 50

local function run_cmd(cmd)
  local job = maki.fn.jobstart(cmd, {})
  local result, err = maki.fn.jobwait(job, 10000) -- 10s timeout
  if err then
    return nil, err
  end
  if result.exit_code ~= 0 then
    return nil, result.stderr or ("exit " .. result.exit_code)
  end
  return result.stdout, nil
end

-- Run a command in a tmux pane: send-keys, poll capture-pane until the
-- prompt reappears, return the captured output.
local function pane_exec(pane_id, cmd, lines)
  local n = lines or CAPTURE_LINES
  local send_job = maki.fn.jobstart(
    string.format("tmux send-keys -t %q -l %q && tmux send-keys -t %q Enter",
      pane_id, cmd, pane_id), {})
  local _, send_err = maki.fn.jobwait(send_job)
  if send_err then
    return nil, "send-keys failed: " .. send_err
  end

  -- Brief pause for the command to start.
  maki.async.sleep(500)

  -- Poll until the prompt reappears (last non-blank line matches a
  -- shell prompt pattern).
  local elapsed = 0
  while elapsed < MAX_WAIT_S * 1000 do
    maki.async.sleep(POLL_MS)
    elapsed = elapsed + POLL_MS

    local cap_job = maki.fn.jobstart(
      string.format("tmux capture-pane -t %q -p -S -%d",
        pane_id, n), {})
    local cap, _ = maki.fn.jobwait(cap_job)
    if not cap or not cap.stdout then break end

    local lines = {}
    for line in cap.stdout:gmatch("([^\n]*)") do
      table.insert(lines, line)
    end
    -- Trim trailing blank lines.
    while #lines > 0 and lines[#lines] == "" do
      table.remove(lines)
    end
    if #lines == 0 then break end

    local last = lines[#lines]
    -- Heuristic: the prompt is back if the last line looks like a shell
    -- prompt (starts with a common prompt char or contains a path with
    -- a trailing $ or >).
    if last:match("^%s*[~$%#>]") or last:match("[/~]%s*$") or
       last:match("^[a-z@.~%-]+%s*[~$#>]") then
      -- Return everything after the echoed command line (first line).
      local out_lines = {}
      local in_output = false
      for _, line in ipairs(lines) do
        if not in_output then
          in_output = true -- skip first line (the echoed command)
        else
          table.insert(out_lines, line)
        end
      end
      return table.concat(out_lines, "\n"), nil
    end
  end
  return nil, "timed out waiting for command to finish"
end

local function system_prompt(wt_dir, branch, repo_root, task_desc, pane_id)
  return string.format([[
MARKER_XK42 - you have received this system prompt.
You are working in a git worktree at %s on branch %s.
The main repo is at %s - do NOT touch it.
Task: %s

Your shell is a tmux pane (%s). The user is watching it.
Every command you run goes into that pane and the user sees it
live. You do NOT have a separate shell.

Rules:
- Use the run_cmd tool to execute any command. It sends the
  command into the tmux pane and returns the output.
- All git commands use -C "%s" (or cd there first).
- Do NOT push. Do NOT merge. Do NOT modify the main repo.
- When finished, summarize what you changed and the commit hash(es).
- You may split the pane to run concurrent commands or open new
  panes for long-running processes. The window is your sandbox.
  Do NOT touch panes or windows outside this one. Do NOT open
  popups.

Skills:
Before performing any specialized operation (committing, pushing,
opening a PR, code review, BDD workflow, etc.), check whether a
matching skill is available and load it. Skills encode repo or
user-specific conventions, confirmation gates, and step-by-step
procedures that override the defaults. If no matching skill exists,
proceed with your best judgment.
]], wt_dir, branch, repo_root, task_desc, pane_id, wt_dir)
end

maki.api.register_command({
  name = "/task",
  description = "Spawn a subagent in an isolated worktree with a tmux window",
  nargs = "+",
  handler = function(opts)
    local task_desc = opts.args
    if not task_desc or task_desc == "" then
      maki.ui.flash("usage: /task <description>")
      return
    end

    maki.async.spawn(function()
      -- Derive a slug from the task description.
      local slug = task_desc:lower():gsub("%s+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
      if #slug > 40 then
        slug = slug:sub(1, 40):gsub("%-+$", "")
      end

      -- Resolve repo root.
      local repo_root, err = run_cmd("git rev-parse --show-toplevel")
      if err then
        maki.ui.flash("task: " .. err)
        return
      end
      repo_root = repo_root:gsub("%s+$", "")

      local repo = repo_root:match("([^/]+)$") or "repo"
      local home = maki.uv.os_homedir() or "~"
      local wt_dir = string.format("%s/.worktrees/%s/%s", home, repo, slug)
      local branch = string.format("worktree/%s", slug)
      local win_name = string.format("wt-%s-%s", repo, slug)

      -- Confirm with the user before creating anything.
      local buf = maki.ui.buf({ scratch = true })
      buf:line(string.format("Task: %s", task_desc))
      buf:line(string.format("Worktree: %s", wt_dir))
      buf:line(string.format("Branch: %s", branch))
      buf:line(string.format("Window: %s", win_name))
      buf:line("")
      buf:line("Launch subagent?")
      local win = maki.ui.open_win(buf, {
        title = "Confirm task",
        width = "40%",
        height = 9,
        anchor = "center",
        footer = { { "y", "launch" }, { "n", "cancel" } },
      })
      local confirmed = false
      while true do
        local ev = win:recv()
        if not ev then break end
        if ev.type == "key" then
          if ev.key == "y" or ev.key == "<CR>" then
            confirmed = true
            break
          elseif ev.key == "n" or ev.key == "<Esc>" then
            break
          end
        elseif ev.type == "close" then
          break
        end
      end
      win:close()
      if not confirmed then
        maki.ui.flash("task: cancelled")
        return
      end

      -- Create the worktree, or reuse it if the branch already exists.
      local existing = run_cmd(
        string.format("git -C %s branch --list %s", repo_root, branch))
      local wt_parent = string.format("%s/.worktrees/%s", home, repo)
      if existing and existing:match("%S") then
        local wt_list = run_cmd(
          string.format("git -C %s worktree list --porcelain", repo_root))
        if not (wt_list and wt_list:find(wt_dir, 1, true)) then
          local _, err = run_cmd(string.format(
            "mkdir -p %q && git -C %q worktree add %q %q",
            wt_parent, repo_root, wt_dir, branch))
          if err then
            maki.ui.flash("task: worktree recreation failed: " .. err)
            return
          end
        end
      else
        local _, err = run_cmd(string.format(
          "mkdir -p %q && git -C %q worktree add %q -b %q",
          wt_parent, repo_root, wt_dir, branch))
        if err then
          maki.ui.flash("task: worktree creation failed: " .. err)
          return
        end
      end

      -- Open the tmux window.
      local session, sess_err = run_cmd("tmux display-message -p '#{session_name}'")
      if sess_err or not session or session:gsub("%s", "") == "" then
        maki.ui.flash("task: tmux not reachable")
        return
      end
      session = session:gsub("%s+$", "")

      -- Reuse the window if it already exists, otherwise create it.
      local pane_id, win_err
      local win_target = string.format("%s:%s", session, win_name)
      local existing_pane = run_cmd(string.format(
        "tmux list-panes -t %q -F '#{pane_id}' 2>/dev/null", win_target))
      if existing_pane and existing_pane:match("%S") then
        pane_id = existing_pane:gsub("%s+$", "")
      else
        pane_id, win_err = run_cmd(string.format(
          "tmux new-window -d -P -F '#{pane_id}' -t %q -n %q -c %q",
          session, win_name, wt_dir))
        if win_err or not pane_id or pane_id:gsub("%s", "") == "" then
          maki.ui.flash("task: tmux window creation failed: " .. (win_err or "no pane id"))
          return
        end
        pane_id = pane_id:gsub("%s+$", "")
      end

      -- Get the current session ID for the agent context.
      local function dlog(msg)
        maki.fs.append("/tmp/maki_task_dbg.log", msg .. "\n")
        maki.ui.flash("task: " .. msg)
      end
      local sid, sid_err = maki.session.current()
      dlog("sid=" .. tostring(sid) .. " err=" .. tostring(sid_err))
      if sid_err then
        maki.ui.flash("task: " .. sid_err)
        return
      end
      if not sid then
        maki.ui.flash("task: no current session")
        return
      end

      -- Build the run_cmd local tool: the subagent's only shell.
      local local_tools = {
        run_cmd = {
          description = "Run a shell command in the tmux pane. "
            .. "The command is sent into the pane and the output "
            .. "is returned. Use this for ALL shell commands - "
            .. "git, ls, grep, make, test, etc. "
            .. "By default the last 50 lines of output are returned; "
            .. "pass 'lines' to get more for verbose commands.",
          input_schema = {
            type = "object",
            properties = {
              command = {
                type = "string",
                description = "The shell command to run",
              },
              lines = {
                type = "integer",
                description = "Number of output lines to capture "
                  .. "(default 50). Use 200+ for verbose builds or "
                  .. "test runs.",
              },
            },
            required = { "command" },
          },
          handler = function(input)
            local out, err = pane_exec(pane_id, input.command, input.lines)
            if err then
              return nil, err
            end
            return out or ""
          end,
        },
      }

      -- Build the tools array for the subagent. Exclude all file and
      -- shell tools so the subagent is forced to use run_cmd for
      -- everything - that's the only way commands show up in the
      -- tmux pane the user is watching.
      local excluded = {
        bash = true, read = true, write = true, edit = true,
        multiedit = true, edit_lines = true, grep = true, glob = true,
      }
      local ok, raw_tools = pcall(maki.api.get_tools)
      if not ok then
        dlog("get_tools failed: " .. tostring(raw_tools))
        raw_tools = {}
      end
      local tools = {}
      for _, t in ipairs(raw_tools) do
        if not excluded[t.name] and t.enabled then
          local schema = t.schema or { type = "object" }
          local desc = schema.description or t.name
          if schema.type == "object" then
            schema = {
              type = "object",
              properties = schema.properties or {},
              required = schema.required,
            }
          end
          table.insert(tools, {
            name = t.name,
            description = desc,
            input_schema = schema,
          })
        end
      end
      dlog("tools count=" .. tostring(#tools))

      -- Create the subagent session.
      local sys = system_prompt(wt_dir, branch, repo_root, task_desc, pane_id)
      dlog("system prompt len=" .. tostring(#sys))
      dlog("system head: " .. sys:sub(1, 60))
      dlog("before maki.agent.session, sid=" .. tostring(sid))
      dlog("before maki.agent.session, system=" .. tostring(sys))
      local sess, sess_err = maki.agent.session({ session = sid }, {
        system = sys,
        tools = tools,
        local_tools = local_tools,
        name = "task-" .. slug,
      })
      dlog("after session: sess=" .. tostring(sess ~= nil) .. " err=" .. tostring(sess_err))
      if sess_err then
        maki.ui.flash("task: failed to create session: " .. sess_err)
        return
      end

      -- Run the task.
      local result, prompt_err = sess:prompt(task_desc)
      sess:close()

      if prompt_err then
        maki.ui.flash("task: " .. prompt_err)
        return
      end

      maki.ui.flash("task: done.")
    end)
  end,
})

maki.log.info("maki_task: /task command registered")
