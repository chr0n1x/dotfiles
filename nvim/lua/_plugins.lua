-- Auto install plugin manager

local fn = vim.fn
local install_path = fn.stdpath('data') ..
  '/site/pack/packer/start/packer.nvim'
if fn.empty(fn.glob(install_path)) > 0 then
  packer_bootstrapped = fn.system(
    {
      'git', 'clone',
      '--depth', '1',
      'https://github.com/wbthomason/packer.nvim',
      install_path
    }
  )
end

return require('packer').startup(
  {
    config = {
        display = {
          open_fn = require('packer.util').float,
        }
    },

    function()
      -- base requirements
      use 'wbthomason/packer.nvim'
      use { 'kyazdani42/nvim-web-devicons', after = 'packer.nvim' }

      -- editing super-chargers
      use {
        "AckslD/nvim-neoclip.lua",
        config = function() require('neoclip').setup() end
      }
      use {
        "folke/zen-mode.nvim",
        config = function() require('plugins/zen-mode') end
      }
      use 'gregsexton/MatchTag'
      use {
          'ms-jpq/coq_nvim',
          after = 'packer.nvim',
          branch = 'coq',
          event = 'VimEnter',
          config = function() require "plugins/coq" end
      }
      use {
        'ms-jpq/coq.artifacts',
        after = 'coq_nvim',
        branch = 'artifacts'
      }
      use {
        'nvim-treesitter/nvim-treesitter',
        run = ':TSUpdate',
        config = function() require 'plugins/treesitter' end
      }
      use {
        'RRethy/nvim-treesitter-endwise',
        requires = { { 'nvim-treesitter/nvim-treesitter' } },
      }
      use 'nvim-treesitter/playground'
      use 'pseewald/vim-anyfold'
      use 'tpope/vim-surround'
      use 'Yggdroot/indentLine'
      use {
        "folke/twilight.nvim",
        config = function() require("twilight").setup() end
      }

      -- finders, navigation
      use { 'ms-jpq/chadtree' }
      use {
        'nvim-telescope/telescope.nvim',
        requires = { {'nvim-lua/plenary.nvim'} }
      }
      use {
        'rcarriga/nvim-notify',
        requires = { {'nvim-telescope/telescope.nvim'} },
        config = function()
          require('telescope').load_extension('notify')
          require 'notify'.setup()
        end
      }
      use {'stevearc/dressing.nvim'}

      -- git things
      use 'airblade/vim-gitgutter'
      use {
        'lewis6991/gitsigns.nvim',
        requires = {
          'nvim-lua/plenary.nvim'
        },
      }
      use 'tpope/vim-fugitive'

      -- misc awesome things
      use 'jamestthompson3/nvim-remote-containers'
      use {
        'hoob3rt/lualine.nvim',
        after = 'nvim-web-devicons',
        event = 'VimEnter',
        config = function() require "plugins/lualine" end
      }
      use 'shaunsingh/nord.nvim'

      if packer_bootstrapped then
        require('packer').sync()
        -- I have no idea if this actually works
        vim.api.nvim_command [[UpdateRemotePlugins]]

        require('nvim-treesitter.configs').setup {
            endwise = { enable = true }
        }
      end
    end
  }
)
