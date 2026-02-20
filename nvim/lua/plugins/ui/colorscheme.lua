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

        -- Индикатор записи макроса - очень заметный!
        hl.MacroRecording = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#dc322f', -- red - яркий и заметный
          bold = true,
        }

        -- Индикатор изменений - красная точка
        hl.ModifiedIndicator = {
          fg = '#dc322f', -- red
          bg = 'NONE',
          bold = true,
        }

        -- Readonly индикатор - оранжевый для предупреждения
        hl.ReadonlyIndicator = {
          fg = '#cb4b16', -- orange
          bg = 'NONE',
          bold = true,
        }

        -- LSP Диагностика - только цветной текст БЕЗ фона
        -- Errors - red
        hl.DiagnosticError = {
          fg = '#dc322f', -- red
          bg = 'NONE',
        }
        hl.DiagnosticVirtualTextError = {
          fg = '#dc322f',
          bg = 'NONE',
        }
        hl.DiagnosticUnderlineError = {
          sp = '#dc322f',
          underline = true,
        }
        hl.DiagnosticSignError = {
          fg = '#dc322f',
          bg = 'NONE',
        }

        -- Warnings - yellow/orange
        hl.DiagnosticWarn = {
          fg = '#b58900', -- yellow
          bg = 'NONE',
        }
        hl.DiagnosticVirtualTextWarn = {
          fg = '#b58900',
          bg = 'NONE',
        }
        hl.DiagnosticUnderlineWarn = {
          sp = '#b58900',
          underline = true,
        }
        hl.DiagnosticSignWarn = {
          fg = '#b58900',
          bg = 'NONE',
        }

        -- Info - blue
        hl.DiagnosticInfo = {
          fg = '#268bd2', -- blue
          bg = 'NONE',
        }
        hl.DiagnosticVirtualTextInfo = {
          fg = '#268bd2',
          bg = 'NONE',
        }
        hl.DiagnosticUnderlineInfo = {
          sp = '#268bd2',
          underline = true,
        }
        hl.DiagnosticSignInfo = {
          fg = '#268bd2',
          bg = 'NONE',
        }

        -- Hints - cyan
        hl.DiagnosticHint = {
          fg = '#2aa198', -- cyan
          bg = 'NONE',
        }
        hl.DiagnosticVirtualTextHint = {
          fg = '#2aa198',
          bg = 'NONE',
        }
        hl.DiagnosticUnderlineHint = {
          sp = '#2aa198',
          underline = true,
        }
        hl.DiagnosticSignHint = {
          fg = '#2aa198',
          bg = 'NONE',
        }

        -- Noice (командная строка и уведомления)
        hl.NoiceCmdlinePopup = {
          bg = c.bg_dark,
          fg = c.fg,
        }
        hl.NoiceCmdlinePopupBorder = {
          bg = c.bg_dark,
          fg = is_dark() and '#2aa198' or '#268bd2', -- cyan/blue
        }
        hl.NoiceCmdlineIcon = {
          bg = c.bg_dark,
          fg = is_dark() and '#b58900' or '#cb4b16', -- yellow/orange
        }
        -- Mini view для макро-рекординга - яркий и заметный
        hl.NoiceMini = {
          bg = is_dark() and '#dc322f' or '#cb4b16', -- red/orange - очень заметно
          fg = is_dark() and '#FDF6E3' or '#002B36',
          bold = true,
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
        -- Режимы statusline в классическом стиле Solarized
        hl.MiniStatuslineModeNormal = {
          fg = is_dark() and '#002B36' or '#FDF6E3', -- инверсия для контраста
          bg = '#2aa198', -- cyan - спокойный основной режим
          bold = true,
        }
        hl.MiniStatuslineModeInsert = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#dc322f', -- red - внимание! редактирование
          bold = true,
        }
        hl.MiniStatuslineModeVisual = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#d33682', -- magenta - выделение
          bold = true,
        }
        hl.MiniStatuslineModeReplace = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#cb4b16', -- orange - замена (яркий акцент)
          bold = true,
        }
        hl.MiniStatuslineModeCommand = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#b58900', -- yellow - команды
          bold = true,
        }
        hl.MiniStatuslineMode = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#268bd2', -- blue - остальные режимы
          bold = true,
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
