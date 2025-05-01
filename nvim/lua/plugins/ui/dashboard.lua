return {
  'goolord/alpha-nvim',
  event = 'VimEnter',
  config = function()
    local alpha = require 'alpha'
    local dashboard = require 'alpha.themes.dashboard'

    local function get_centered_header()
      local header = { 'GO BIG OR GO HOME' }
      local centered_header = {}
      local lines = vim.api.nvim_win_get_height(0)
      local empty_lines = math.floor(((lines - #header) / 2) - 1)

      for i = 1, empty_lines do
        table.insert(centered_header, '')
      end

      for _, line in ipairs(header) do
        table.insert(centered_header, line)
      end

      return centered_header
    end

    dashboard.section.buttons.val = {}
    dashboard.section.header.val = get_centered_header()
    dashboard.section.header.opts = { position = 'center', hl = 'AlphaHeader', }

    vim.cmd [[highlight AlphaHeader guifg=#ff6347 guibg=NONE gui=bold]]

    alpha.setup(dashboard.config)
  end,
}
