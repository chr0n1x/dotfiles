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
  function()
    -- base requirements
    use 'wbthomason/packer.nvim'
    use { 'kyazdani42/nvim-web-devicons', after = 'packer.nvim' }

    -- editing super-chargers
    use 'gregsexton/MatchTag'
    use 'pseewald/vim-anyfold'
    use 'tpope/vim-surround'
    use 'Yggdroot/indentLine'
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
      "folke/zen-mode.nvim",
      config = function() require('plugins/zen-mode') end
    }
    use {
      'nvim-treesitter/nvim-treesitter',
      run = ':TSUpdate',
      config = function() require 'plugins/treesitter' end
    }
    use 'nvim-treesitter/playground'

    -- finders, navigation
    use 'kien/ctrlp.vim'
    use 'scrooloose/nerdtree'
    use {
      'nvim-telescope/telescope.nvim',
      requires = { {'nvim-lua/plenary.nvim'} }
    }

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
    use 'shaunsingh/nord.nvim'
    use {
        'hoob3rt/lualine.nvim',
        after = { 'nvim-web-devicons' },
        event = 'VimEnter',
        config = function() require "plugins/lualine" end
    }

    if packer_bootstrapped then
      require('packer').sync()
      vim.api.nvim_command [[UpdateRemotePlugins<C-R>]]
    end
  end
)
