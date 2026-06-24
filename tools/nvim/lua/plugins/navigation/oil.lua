return {
  'stevearc/oil.nvim',
  ---@module 'oil'
  ---@type oil.SetupOpts
  opts = {
    -- следить за изменениями директории (создание/удаление файлов в терминале, git checkout)
    experimental_watch_for_changes = true,
    view_options = {
      show_hidden = true,
    },
  },
  dependencies = {
    { 'echasnovski/mini.icons', opts = {} },
  },
  keys = {
    {
      '\\',
      function()
        require('oil').open()
      end,
      desc = 'Open oil.nvim in float',
      silent = true,
    },
  },
  lazy = false,
}
