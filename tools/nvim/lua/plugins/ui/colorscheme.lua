return {
  'craftzdog/solarized-osaka.nvim',
  lazy = false,
  priority = 1000,
  opts = function()
    return {
      -- вариант тёмной палитры (storm/night/day); фиксируем явно
      style = 'night',
      -- Normal/NormalNC/LineNr → NONE штатным механизмом темы (вместо ручных highlight в init)
      transparent = true,
      styles = {
        -- floats/sidebars прозрачны: c.bg_float=NONE каскадом уходит в NormalFloat,
        -- FloatBorder, BlinkCmpDoc, SnacksPickerBorder и прочие плавающие группы
        sidebars = 'transparent',
        floats = 'transparent',
      },
      -- Семантические алиасы цветов: точные значения, что использует конфиг (стандартный
      -- solarized — НЕ палитра темы, та чуть иные оттенки), поэтому без визуального сдвига.
      -- bg_dark='NONE' централизует прозрачность вместо локальной переменной.
      on_colors = function(c)
        c.bg_dark = 'NONE' -- весь UI прозрачный (вместо локальной переменной)
        -- стандартные solarized-акценты (точные значения конфига; палитра темы чуть иная)
        c.sol_red = '#dc322f'
        c.sol_yellow = '#b58900'
        c.sol_blue = '#268bd2'
        c.sol_cyan = '#2aa198'
        c.muted = '#586e75' -- мутный серый (blame)
        -- приглушённые тинты inline word-diff (gitsigns)
        c.gs_add = '#0f3a28'
        c.gs_change = '#3a3418'
        c.gs_delete = '#4a1f1f'
        c.gs_add_l = '#c7e6c7'
        c.gs_change_l = '#e8e0b0'
        c.gs_delete_l = '#e8c0c0'
      end,
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
        hl.DiagnosticError = { fg = c.sol_red, bg = 'NONE' }
        hl.DiagnosticVirtualTextError = { fg = c.sol_red, bg = 'NONE' }
        hl.DiagnosticUnderlineError = { sp = c.sol_red, underline = true }
        hl.DiagnosticSignError = { fg = c.sol_red, bg = 'NONE' }

        -- Warnings - yellow
        hl.DiagnosticWarn = { fg = c.sol_yellow, bg = 'NONE' }
        hl.DiagnosticVirtualTextWarn = { fg = c.sol_yellow, bg = 'NONE' }
        hl.DiagnosticUnderlineWarn = { sp = c.sol_yellow, underline = true }
        hl.DiagnosticSignWarn = { fg = c.sol_yellow, bg = 'NONE' }

        -- Info - blue
        hl.DiagnosticInfo = { fg = c.sol_blue, bg = 'NONE' }
        hl.DiagnosticVirtualTextInfo = { fg = c.sol_blue, bg = 'NONE' }
        hl.DiagnosticUnderlineInfo = { sp = c.sol_blue, underline = true }
        hl.DiagnosticSignInfo = { fg = c.sol_blue, bg = 'NONE' }

        -- Hints - cyan
        hl.DiagnosticHint = { fg = c.sol_cyan, bg = 'NONE' }
        hl.DiagnosticVirtualTextHint = { fg = c.sol_cyan, bg = 'NONE' }
        hl.DiagnosticUnderlineHint = { sp = c.sol_cyan, underline = true }
        hl.DiagnosticSignHint = { fg = c.sol_cyan, bg = 'NONE' }

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

        -- LSP подсветка одинаковых символов — только фон, БЕЗ подчёркивания
        hl.LspReferenceText = { bg = is_dark() and '#073642' or '#eee8d5' } -- base02/base2
        hl.LspReferenceRead = { bg = is_dark() and '#073642' or '#eee8d5' }
        hl.LspReferenceWrite = { bg = is_dark() and '#073642' or '#eee8d5' }

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
        hl.EndOfBuffer = { bg = 'NONE' } -- transparent покрывает Normal/NormalNC/LineNr, но не EndOfBuffer
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
        -- word_diff (gitsigns): inline-подсветка изменённых слов. На прозрачной теме
        -- без явного фона невидима — задаём приглушённые тинты в solarized-палитре.
        hl.GitSignsAddLnInline = { bg = is_dark() and c.gs_add or c.gs_add_l }
        hl.GitSignsChangeLnInline = { bg = is_dark() and c.gs_change or c.gs_change_l }
        hl.GitSignsDeleteLnInline = { bg = is_dark() and c.gs_delete or c.gs_delete_l }
        -- DiffAdd: тема красит добавление бирюзовым (#103a3c, читается синим). Делаем зелёным —
        -- одним override закрываются ВСЕ diff-превью: gitsigns float (GitSignsAddPreview→DiffAdd),
        -- :diffthis и snacks git-превью (treesitter @diff.plus→DiffAdd).
        hl.DiffAdd = { bg = is_dark() and c.gs_add or c.gs_add_l }
        -- blame текущей строки — мутно, курсивом, без жирного, чтобы не тянуть внимание
        hl.GitSignsCurrentLineBlame = { fg = c.muted, italic = true }

        -- snacks.dashboard: красный header (текст + волны), серый футер со временем
        hl.SnacksDashboardHeader = { fg = '#dc322f', bold = true }
        hl.SnacksDashboardFooter = { fg = is_dark() and c.muted or '#93a1a1' }

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
        hl.BlinkCmpMenuBorder = { bg = 'NONE', fg = c.muted }
        hl.BlinkCmpMenuSelection = { bg = is_dark() and '#073642' or '#eee8d5', bold = true }
        hl.BlinkCmpDoc = { bg = 'NONE', fg = c.fg }
        hl.BlinkCmpDocBorder = { bg = 'NONE', fg = c.muted }
        hl.BlinkCmpDocSeparator = { bg = 'NONE', fg = c.muted }
        hl.BlinkCmpSignatureHelp = { bg = 'NONE', fg = c.fg }
        hl.BlinkCmpSignatureHelpBorder = { bg = 'NONE', fg = c.muted }

        -- snacks.picker: прозрачный фон, рамки приглушённым серым (как blink)
        hl.SnacksPicker = { bg = 'NONE', fg = c.fg }
        hl.SnacksPickerBorder = { bg = 'NONE', fg = c.muted }
        hl.SnacksPickerInput = { bg = 'NONE', fg = c.fg }
        hl.SnacksPickerInputBorder = { bg = 'NONE', fg = c.muted }
        hl.SnacksPickerInputSearch = { bg = 'NONE', fg = is_dark() and '#b58900' or '#cb4b16' }
        hl.SnacksPickerList = { bg = 'NONE', fg = c.fg }
        hl.SnacksPickerListBorder = { bg = 'NONE', fg = c.muted }
        hl.SnacksPickerPreview = { bg = 'NONE', fg = c.fg }
        hl.SnacksPickerPreviewBorder = { bg = 'NONE', fg = c.muted }
        hl.SnacksPickerPreviewTitle = { bg = 'NONE', fg = is_dark() and '#2aa198' or '#268bd2', bold = true }
        hl.SnacksPickerBoxBorder = { bg = 'NONE', fg = c.muted }
        hl.SnacksPickerTitle = { bg = 'NONE', fg = is_dark() and '#2aa198' or '#268bd2', bold = true }
        -- заголовки на рамке ("files" сверху) — прозрачный фон вместо тёмного FloatTitle
        hl.SnacksPickerBorderTitle = { bg = 'NONE', fg = is_dark() and '#2aa198' or '#268bd2', bold = true }
        hl.SnacksPickerInputTitle = { bg = 'NONE', fg = is_dark() and '#2aa198' or '#268bd2', bold = true }
        hl.SnacksPickerListTitle = { bg = 'NONE', fg = is_dark() and '#2aa198' or '#268bd2', bold = true }
        hl.FloatTitle = { bg = 'NONE', fg = is_dark() and '#2aa198' or '#268bd2', bold = true }
        -- подсветка совпадений в результатах поиска — жёлтая (не красный Special)
        hl.SnacksPickerMatch = { fg = '#b58900', bold = true }
        hl.SnacksPickerDir = { fg = c.muted }
        hl.BlinkCmpSignatureHelpActiveParameter = { fg = is_dark() and '#cb4b16' or '#dc322f', bold = true }
      end,
    }
  end,
  init = function()
    vim.cmd.colorscheme 'solarized-osaka'
    -- Ручные `highlight … guibg=NONE` больше не нужны: transparent=true и
    -- styles.floats/sidebars='transparent' делают Normal/NormalNC/NormalFloat/
    -- FloatBorder прозрачными внутри темы; EndOfBuffer добит в on_highlights.
  end,
}
