return {
  'craftzdog/solarized-osaka.nvim',
  lazy = false,
  priority = 1000,
  opts = function()
    return {
      on_highlights = function(hl, c)
        -- Telescope
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

        -- WhichKey
        hl.WhichKey = {
          bg = c.bg_highlight, -- или любой другой цвет
          fg = c.fg,
        }
        hl.WhichKeyTitle = {
          bg = c.bg_highlight,
          fg = c.fg,
        }
        hl.WhichKeyBorder = {
          bg = c.bg_highlight,
          fg = c.fg,
        }
        hl.WhichKeyFloat = {
          bg = c.bg_highlight,
        }

        -- GitSigns
        hl.FloatBorder = {
          bg = c.bg_dark,
          fg = c.fg
        }
        hl.NormalFloat = {
          bg = c.bg_dark,
          fg = c.fg
        }
        hl.GitSignsAdd = {
          bg = c.bg_dark,
          fg = c.green
        }
        hl.GitSignsChange = {
          bg = c.bg_dark,
          fg = c.yellow
        }
        hl.GitSignsDelete = {
          bg = c.bg_dark,
          fg = c.red
        }
      end,
    }
  end,
  init = function()
    vim.cmd.colorscheme 'solarized-osaka'
    vim.cmd [[highlight Normal guibg=NONE ctermbg=NONE]]
    vim.cmd [[highlight NormalNC guibg=NONE ctermbg=NONE]]
    vim.cmd [[highlight EndOfBuffer guibg=NONE ctermbg=NONE]]
    vim.cmd [[highlight FloatBorder guibg=NONE ctermbg=NONE]]
    vim.cmd [[highlight NormalFloat guibg=NONE ctermbg=NONE]]
  end,
}
