-- Global maki config. maki loads the first init.lua it finds across
-- ~/.maki and ~/.config/maki and stops; subdirectories are not discovered,
-- so each customization is required here. `require` in a config init.lua
-- searches <config dir>/lua (the same root plugin.toml declares), so
-- smooth_scroll.lua becomes require("smooth_scroll").
local ok, err = pcall(require, "smooth_scroll")
if not ok then
  maki.log.warn("smooth_scroll: " .. tostring(err))
end

local ok_gate, err_gate = pcall(require, "gate")
if not ok_gate then
  maki.log.warn("gate: " .. tostring(err_gate))
end

maki.setup({
  -- actually yolo'ing like the millenial I am
  always_yolo = true,
  -- 27B models get really dumb past 150k
  -- and I've seen larger models get stupid around 50% of their max
  agent = { compaction_buffer = "30%" },
})

maki.api.register_command({
  name = "/resume",
  description = "Alias for /sessions",
  handler = function()
    local ok, err = maki.api.run_command("/sessions")
    if not ok then
      maki.ui.flash("could not run /sessions: " .. err)
    end
  end,
})
