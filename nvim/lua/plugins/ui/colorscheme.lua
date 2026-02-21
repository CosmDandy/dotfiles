return {
  'craftzdog/solarized-osaka.nvim',
  lazy = false,
  priority = 1000,
  opts = function()
    return {
      on_highlights = function(hl, c)
        -- Проверяем background динамически
        local function is_dark()
          return vim.o.background == 'dark'
        end

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
        hl.TelescopeSelection = {
          bg = is_dark() and '#073642' or '#eee8d5', -- base02 для темной, base2 для светлой
          fg = is_dark() and c.fg or '#002B36', -- стандартный fg для темной, base03 для светлой
        }
        hl.TelescopeSelectionCaret = {
          fg = is_dark() and c.red or '#DC322F', -- accent цвет
          bg = is_dark() and '#073642' or '#eee8d5',
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
          bg = is_dark() and '#073642' or '#eee8d5', -- base02 для темной, base2 для светлой
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

        -- Текущая строка
        hl.CursorLine = {
          bg = is_dark() and '#073642' or '#eee8d5', -- base02 для темной, base2 для светлой
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

        -- Курсор - cyan accent color
        hl.Cursor = {
          fg = is_dark() and '#002B36' or '#FDF6E3', -- base03 для темной, base3 для светлой
          bg = '#2aa198', -- cyan для обеих тем
        }
        hl.lCursor = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#2aa198',
        }
        hl.CursorIM = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#2aa198',
        }

        -- Парные скобки - orange с инверсией для максимальной заметности
        hl.MatchParen = {
          fg = is_dark() and '#002B36' or '#FDF6E3', -- темный на светлом или светлый на темном
          bg = '#cb4b16', -- orange фон
          bold = true,
        }

        -- LSP подсветка одинаковых символов - cyan underline на легком фоне
        hl.LspReferenceText = {
          bg = is_dark() and '#073642' or '#eee8d5', -- base02/base2
          underline = true,
          sp = '#2aa198', -- cyan для underline
        }
        hl.LspReferenceRead = {
          bg = is_dark() and '#073642' or '#eee8d5',
          underline = true,
          sp = '#268bd2', -- blue для read
        }
        hl.LspReferenceWrite = {
          bg = is_dark() and '#073642' or '#eee8d5',
          underline = true,
          sp = '#cb4b16', -- orange для write (более заметно)
        }

        -- Alpha dashboard header - orange bold "GO BIG OR GO HOME"
        hl.AlphaHeader = {
          fg = '#cb4b16', -- orange
          bold = true,
        }

        -- Выделение
        hl.Visual = {
          bg = is_dark() and '#073642' or '#93a1a1', -- base02 для темной, base1 для светлой
          fg = is_dark() and '#FDF6E3' or '#002B36', -- base3 для темной, base03 для светлой
          bold = true, -- Делаем текст жирным для лучшей видимости
        }

        -- Поиск
        hl.Search = {
          bg = is_dark() and '#B58900' or '#CB4B16', -- Желтый для темной, Оранжевый для светлой
          fg = is_dark() and '#002B36' or '#FDF6E3', -- base03 для темной, base3 для светлой
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
