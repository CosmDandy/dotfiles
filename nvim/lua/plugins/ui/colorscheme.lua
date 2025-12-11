return {
  'craftzdog/solarized-osaka.nvim',
  lazy = false,
  priority = 1000,
  opts = function()
    return {
      on_highlights = function(hl, c)
        local is_dark = vim.o.background == 'dark'

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

        -- WhichKey с прозрачным фоном
        hl.WhichKey = {
          bg = 'NONE', -- прозрачный фон
          fg = c.fg,
        }
        hl.WhichKeyTitle = {
          bg = 'NONE',
          fg = c.fg,
        }
        hl.WhichKeyBorder = {
          bg = 'NONE',
          fg = c.fg,
        }
        hl.WhichKeyFloat = {
          bg = 'NONE',
        }
        hl.WhichKeyDesc = {
          bg = 'NONE',
        }
        hl.WhichKeyGroup = {
          bg = 'NONE',
        }
        hl.WhichKeySeparator = {
          bg = 'NONE',
        }
        hl.WhichKeyValue = {
          bg = 'NONE',
        }

        hl.TreesitterContext = {
          bg = is_dark and '#073642' or '#151003',
        }

        -- Barbecue (winbar) с прозрачным фоном
        hl.BarbecueNormal = {
          bg = 'NONE',
        }
        hl.BarbecueEllipsis = {
          bg = 'NONE',
        }
        hl.BarbecueSeparator = {
          bg = 'NONE',
        }
        hl.BarbecueDirectory = {
          bg = 'NONE',
        }
        hl.BarbecueDirectoryBasename = {
          bg = 'NONE',
        }
        hl.BarbecueContext = {
          bg = 'NONE',
        }
        hl.BarbecueContextPrefix = {
          bg = 'NONE',
        }
        hl.BarbecueContextSuffix = {
          bg = 'NONE',
        }
        hl.BarbecueModified = {
          bg = 'NONE',
        }

        -- Статусная строка (mini.statusline) с прозрачным фоном
        hl.StatusLine = {
          bg = 'NONE',
        }
        hl.StatusLineNC = {
          bg = 'NONE',
        }
        hl.MiniStatuslineDevinfo = {
          bg = 'NONE',
        }
        hl.MiniStatuslineFilename = {
          bg = 'NONE',
        }
        hl.MiniStatuslineFileinfo = {
          bg = 'NONE',
        }
        hl.MiniStatuslineInactive = {
          bg = 'NONE',
        }
        hl.MiniStatuslineModeNormal = {
          bg = 'NONE',
        }
        hl.MiniStatuslineModeInsert = {
          bg = 'NONE',
        }
        hl.MiniStatuslineModeVisual = {
          bg = 'NONE',
        }
        hl.MiniStatuslineModeReplace = {
          bg = 'NONE',
        }
        hl.MiniStatuslineModeCommand = {
          bg = 'NONE',
        }
        hl.MiniStatuslineMode = {
          bg = 'NONE',
        }

        -- Текущая строка с прозрачным фоном
        hl.CursorLine = {
          bg = is_dark and '#073642' or '#151003',
        }
        hl.LineNr = {
          fg = '#576d74',
        }
        hl.LineNrAbove = {
          fg = '#576d74',
        }
        hl.LineNrBelow = {
          fg = '#576d74',
        }

        -- Выделение
        hl.Visual = {
          bg = is_dark and '#073642' or '#151003',
          fg = is_dark and '#FDF6E3' or '#FDF6E3', -- base3 (светлый текст)
          bold = true, -- Делаем текст жирным для лучшей видимости
        }

        -- Поиск
        hl.Search = {
          bg = is_dark and '#B58900' or '#CB4B16', -- Желтый для темной, Оранжевый для светлой
          fg = is_dark and '#002B36' or '#FDF6E3', -- base03 для темной, base3 для светлой
          bold = true,
        }

        -- GitSigns
        hl.FloatBorder = {
          bg = c.bg_dark,
          fg = c.fg,
        }
        hl.NormalFloat = {
          bg = c.bg_dark,
          fg = c.fg,
        }
        hl.GitSignsAdd = {
          bg = c.bg_dark,
          fg = c.green,
        }
        hl.GitSignsChange = {
          bg = c.bg_dark,
          fg = c.yellow,
        }
        hl.GitSignsDelete = {
          bg = c.bg_dark,
          fg = c.red,
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
