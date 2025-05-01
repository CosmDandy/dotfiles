return {
  'stevearc/oil.nvim',
  ---@module 'oil'
  ---@type oil.SetupOpts
  opts = {
    delete_to_trash = true,
    view_options = {
      show_hidden = true,
    }
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
