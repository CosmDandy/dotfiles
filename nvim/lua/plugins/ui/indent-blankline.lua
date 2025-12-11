-- indent-blankline - визуализация уровней отступов
return {
  'lukas-reineke/indent-blankline.nvim',
  event = { 'BufReadPost', 'BufNewFile' },
  main = 'ibl',
  opts = {
    indent = {
      char = '┊',
      tab_char = '│',
      highlight = 'IblScope',
      smart_indent_cap = true,
      priority = 1,
    },
    scope = {
      enabled = true,
      char = '│',
      show_start = true,
      show_end = false,
      injected_languages = false,
      highlight = { 'Function', 'Label' },
      priority = 500,
    },
    exclude = {
      filetypes = {
        'help',
        'alpha',
        'dashboard',
        'neo-tree',
        'Trouble',
        'trouble',
        'lazy',
        'mason',
        'notify',
        'toggleterm',
        'lazyterm',
      },
    },
  },
}
