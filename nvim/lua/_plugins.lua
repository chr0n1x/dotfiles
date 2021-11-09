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
    use { 'ms-jpq/chadtree' }
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
    use {
      'kunzaatko/nord.nvim',
      requires = { 'rktjmp/lush.nvim' },
      -- hack - https://github.com/kunzaatko/nord.nvim/issues/5
      config = function() vim.cmd("colorscheme nord") end,
      after = { 'lush.nvim' },
      cond = true
    }
    use 'jamestthompson3/nvim-remote-containers'
    use {
        'hoob3rt/lualine.nvim',
        after = { 'nvim-web-devicons' },
        event = 'VimEnter',
        config = function() require "plugins/lualine" end
    }

    if packer_bootstrapped then
      require('packer').sync()
      vim.api.nvim_command [[UpdateRemotePlugins]]
    end
  end
)
