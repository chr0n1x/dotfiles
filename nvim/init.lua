require('_plugins')

require('autocmds')
require('colors')
require('base-settings')
require('key-bindings')

-- called with no other arguments (i.e.: command was just `nvim`)
if #vim.v.argv == 1 then
  require('telescope.builtin').find_files()
end
