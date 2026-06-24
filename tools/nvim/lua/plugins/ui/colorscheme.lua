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

        -- snacks.dashboard: красный header (текст + волны), серый футер со временем
        hl.SnacksDashboardHeader = { fg = '#dc322f', bold = true }
        hl.SnacksDashboardFooter = { fg = is_dark() and '#586e75' or '#93a1a1' }

        -- snacks.indent: явные цвета (по дефолту линкуется на NonText, почти невидим)
        hl.SnacksIndent = { fg = is_dark() and '#3a4d52' or '#93a1a1' } -- тусклые гайды на всех уровнях
        hl.SnacksIndentScope = { fg = is_dark() and '#2aa198' or '#268bd2' } -- cyan/blue для активного
        hl.SnacksIndent1 = { fg = '#268bd2' } -- blue
        hl.SnacksIndent2 = { fg = '#2aa198' } -- cyan
        hl.SnacksIndent3 = { fg = '#859900' } -- green
        hl.SnacksIndent4 = { fg = '#b58900' } -- yellow
        hl.SnacksIndent5 = { fg = '#cb4b16' } -- orange
        hl.SnacksIndent6 = { fg = '#d33682' } -- magenta

        -- blink.cmp: фон такой же, как основной редактор (прозрачный)
        hl.BlinkCmpMenu = { bg = 'NONE', fg = c.fg }
        hl.BlinkCmpMenuBorder = { bg = 'NONE', fg = '#586e75' }
        hl.BlinkCmpMenuSelection = { bg = is_dark() and '#073642' or '#eee8d5', bold = true }
        hl.BlinkCmpDoc = { bg = 'NONE', fg = c.fg }
        hl.BlinkCmpDocBorder = { bg = 'NONE', fg = '#586e75' }
        hl.BlinkCmpDocSeparator = { bg = 'NONE', fg = '#586e75' }
        hl.BlinkCmpSignatureHelp = { bg = 'NONE', fg = c.fg }
        hl.BlinkCmpSignatureHelpBorder = { bg = 'NONE', fg = '#586e75' }

        -- snacks.picker: прозрачный фон, рамки приглушённым серым (как blink)
        hl.SnacksPicker = { bg = 'NONE', fg = c.fg }
        hl.SnacksPickerBorder = { bg = 'NONE', fg = '#586e75' }
        hl.SnacksPickerInput = { bg = 'NONE', fg = c.fg }
        hl.SnacksPickerInputBorder = { bg = 'NONE', fg = '#586e75' }
        hl.SnacksPickerInputSearch = { bg = 'NONE', fg = is_dark() and '#b58900' or '#cb4b16' }
        hl.SnacksPickerList = { bg = 'NONE', fg = c.fg }
        hl.SnacksPickerListBorder = { bg = 'NONE', fg = '#586e75' }
        hl.SnacksPickerPreview = { bg = 'NONE', fg = c.fg }
        hl.SnacksPickerPreviewBorder = { bg = 'NONE', fg = '#586e75' }
        hl.SnacksPickerPreviewTitle = { bg = 'NONE', fg = is_dark() and '#2aa198' or '#268bd2', bold = true }
        hl.SnacksPickerBoxBorder = { bg = 'NONE', fg = '#586e75' }
        hl.SnacksPickerTitle = { bg = 'NONE', fg = is_dark() and '#2aa198' or '#268bd2', bold = true }
        -- заголовки на рамке ("files" сверху) — прозрачный фон вместо тёмного FloatTitle
        hl.SnacksPickerBorderTitle = { bg = 'NONE', fg = is_dark() and '#2aa198' or '#268bd2', bold = true }
        hl.SnacksPickerInputTitle = { bg = 'NONE', fg = is_dark() and '#2aa198' or '#268bd2', bold = true }
        hl.SnacksPickerListTitle = { bg = 'NONE', fg = is_dark() and '#2aa198' or '#268bd2', bold = true }
        hl.FloatTitle = { bg = 'NONE', fg = is_dark() and '#2aa198' or '#268bd2', bold = true }
        -- подсветка совпадений в результатах поиска — жёлтая (не красный Special)
        hl.SnacksPickerMatch = { fg = '#b58900', bold = true }
        hl.SnacksPickerDir = { fg = '#586e75' }
        hl.BlinkCmpSignatureHelpActiveParameter = { fg = is_dark() and '#cb4b16' or '#dc322f', bold = true }
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
