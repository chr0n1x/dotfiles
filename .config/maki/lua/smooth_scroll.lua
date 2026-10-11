-- Smooth, inertial transcript scrolling in normal mode. <C-u>/<C-d> glide
-- a half page with a fast-start, slow-stop ease-out; a new press in the same
-- direction retargets the glide (hold to keep going), an opposite press
-- stops it.
--
-- Only control chars are bound: maki.keymap.set has no mode gating in
-- practice (keymap.rs:393), so a letter binding would swallow that letter
-- while typing in insert mode.

local TICK_MS = 16 -- ~60 fps
local TAPS = 28 -- glide duration in ticks (~0.45s); more = longer, gentler

local function view()
  local v, err = maki.fn.winsaveview()
  if not v then
    return nil, err
  end
  return v
end

local function set_topline(topline)
  return maki.fn.winrestview({ topline = topline })
end

-- ease-out: the step on tick i is TAPS + 1 - i (big first, one last);
-- the sum over TAPS ticks is TAPS*(TAPS+1)/2.
local TOTAL = TAPS * (TAPS + 1) / 2

local glide = { task = nil, dir = 0 }

local function stop_glide()
  if glide.task then
    glide.task:cancel()
    glide.task = nil
  end
end

local function start_glide(dir)
  if glide.dir == -dir then -- opposite press kills the current glide
    stop_glide()
    glide.dir = 0
    return
  end
  if glide.task then -- same direction: retarget from the current topline
    stop_glide()
  end
  glide.dir = dir

  local v, err = view()
  if not v then
    glide.dir = 0
    return nil, err
  end

  -- scale the trajectory to one half page, keeping the eased shape;
  -- the UI clamps at the true edges
  local half = math.max(1, math.floor(v.height / 2))
  local step = {}
  for i = 1, TAPS do
    step[i] = math.floor(dir * half * (TAPS + 1 - i) / TOTAL)
  end

  glide.task = maki.async.spawn(function()
    local topline = v.topline
    for i = 1, TAPS do
      topline = topline + step[i]
      set_topline(topline)
      maki.async.sleep(TICK_MS)
    end
    glide.task = nil
    glide.dir = 0
  end)
end

maki.keymap.set("n", "<C-u>", function() start_glide(-1) end, { desc = "Smooth scroll up" })
maki.keymap.set("n", "<C-d>", function() start_glide(1) end, { desc = "Smooth scroll down" })
maki.log.info("smooth_scroll: keymaps registered")
