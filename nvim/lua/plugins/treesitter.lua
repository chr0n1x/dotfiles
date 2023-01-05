require('nvim-treesitter.configs').setup {
  ensure_installed = {'vim', 'lua', 'bash', 'yaml', 'json', 'hcl', 'make' },
  highlight = {
    enable = true,
    additional_vim_regex_highlighting = false,
    use_languagetree = true
  },
  indent = {
    enable = true
  }
}
