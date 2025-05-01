return {
  'akinsho/toggleterm.nvim',
  event = "VeryLazy",
  version = '*',
  config = function()
    require('toggleterm').setup()

    local function _toggle(app)
      local Terminal = require('toggleterm.terminal').Terminal:new {
        cmd = app,
        hidden = true,
        direction = 'float',
        float_opts = {
          border = 'curved',
          width = math.floor(vim.o.columns * 0.9),
          height = math.floor(vim.o.lines * 0.9),
        },
      }
      Terminal:toggle()
    end

    vim.keymap.set('n', '<leader>td', function()
      _toggle 'lazydocker'
    end, { desc = 'LazyDocker' })
    vim.keymap.set('n', '<leader>tb', function()
      _toggle 'btop'
    end, { desc = 'Btop' })
  end,
}
