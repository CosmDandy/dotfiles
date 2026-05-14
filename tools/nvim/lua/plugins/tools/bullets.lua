return {
  {
    'bullets-vim/bullets.vim',
    ft = { 'markdown', 'text' },
    init = function()
      vim.g.bullets_enabled_file_types = { 'markdown', 'text' }
      vim.g.bullets_checkbox_markers = ' .oOX'
      vim.g.bullets_outline_levels = { 'ROM', 'ABC', 'num', 'abc', 'rom', 'std-' }
    end,
  },
}
