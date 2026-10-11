-- Global maki config. maki loads the first init.lua it finds across
-- ~/.maki and ~/.config/maki and stops; subdirectories are not discovered,
-- so each customization is required here. `require` in a config init.lua
-- searches <config dir>/lua (the same root plugin.toml declares), so
-- smooth_scroll.lua becomes require("smooth_scroll").
local ok, err = pcall(require, "smooth_scroll")
if not ok then
  maki.log.warn("smooth_scroll: " .. tostring(err))
end
