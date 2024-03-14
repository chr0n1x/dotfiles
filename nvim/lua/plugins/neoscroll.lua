require('neoscroll').setup({
    hide_cursor = true,            -- Hide cursor while scrolling
    stop_eof = true,               -- Stop at <EOF> when scrolling downwards
    respect_scrolloff = false,     -- Stop scrolling when the cursor reaches the scrolloff margin of the file
    cursor_scrolls_alone = false,  -- The cursor will keep on scrolling even if the window cannot scroll further
    easing_function = 'quadratic', -- Default easing function
    pre_hook = nil,                -- Function to run before the scrolling animation starts
    post_hook = nil,               -- Function to run after the scrolling animation ends
    performance_mode = false,      -- Disable "Performance Mode" on all buffers.
})

local mappings = {}
mappings['<C-b>'] = {'scroll', {'-vim.api.nvim_win_get_height(0)', 'true', '125', [['quadratic']]}}
mappings['<C-f>'] = {'scroll', { 'vim.api.nvim_win_get_height(0)', 'true', '125', [['quadratic']]}}

require('neoscroll.config').set_mappings(mappings)