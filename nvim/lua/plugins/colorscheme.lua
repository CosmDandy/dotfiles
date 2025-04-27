return {
  {
    'craftzdog/solarized-osaka.nvim',
    lazy = false,
    priority = 1000,
    opts = function()
      return {
        -- transparent = true,
        on_highlights = function(hl, c)
          hl.TelescopeNormal = {
            bg = c.bg_dark,
            fg = c.fg_dark,
          }
          hl.TelescopeBorder = {
            bg = c.bg_dark,
            fg = c.bg_dark,
          }
          hl.TelescopePromptNormal = {
            bg = c.bg_dark,
            fg = c.bg_dark,
          }
          hl.TelescopePromptBorder = {
            bg = c.bg_dark,
            fg = c.bg_dark,
          }
          hl.TelescopePromptTitle = {
            bg = c.bg_dark,
            fg = c.bg_dark,
          }
          hl.TelescopePreviewTitle = {
            bg = c.bg_dark,
            fg = c.bg_dark,
          }
          hl.TelescopeResultsTitle = {
            bg = c.bg_dark,
            fg = c.bg_dark,
          }
          local border_c = c.fg
          -- WhichKey
          hl.WhichKeyNormal = {
            bg = c.bg_highlight,
          }
          hl.WhichKeyTitle = {
            bg = c.bg_highlight,
          }
          hl.WhichKeyBorder = {
            fg = border_c,
          }
          -- GitSigns
          hl.FloatBorder = {
            bg = c.bg_dark,
            fg = border_c
          }
          hl.NormalFloat = {
            bg = c.bg_dark,
            fg = border_c
          }
          -- indent
          -- hl.IndentBlanklineChar = {
          --   fg = c.fg,
          --   bg = c.fg,
          -- }
          -- hl.IblIndent = {
          --   fg = c.fg,
          --   bg = c.fg,
          -- }
          -- Oil
          hl.OilFloat = {
            bg = c.bg_highlight
          }
          hl.OilBorder = {
            bg = c.bg_highlight,
            fg = border_c
          }
        end,
      }
    end,
    init = function()
      vim.cmd.colorscheme 'solarized-osaka'
      -- vim.api.nvim_set_hl(0, "OilBorder", { fg = "#ff0000", bg = "none" }) -- Красный цвет
      vim.cmd [[highlight Normal guibg=NONE ctermbg=NONE]]
      vim.cmd [[highlight NormalNC guibg=NONE ctermbg=NONE]]
      vim.cmd [[highlight EndOfBuffer guibg=NONE ctermbg=NONE]]
    end,
  },
  {
    'goolord/alpha-nvim',
    config = function()
      local alpha = require 'alpha'
      local dashboard = require 'alpha.themes.dashboard'

      vim.cmd [[highlight AlphaHeader guifg=#ff6347 guibg=NONE gui=bold]]

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

      dashboard.section.header.val = get_centered_header()
      dashboard.section.header.opts = {
        position = 'center',
        hl = 'AlphaHeader',
      }

      dashboard.section.buttons.val = {}

      alpha.setup(dashboard.config)
    end,
  },
}
