return {
  'craftzdog/solarized-osaka.nvim',
  lazy = false,
  priority = 1000,
  opts = function()
    return {
      style = 'night',
      -- transparent + the styles below hand Normal/NormalNC/LineNr and every floating
      -- group NONE through the theme's own mechanism, instead of manual highlights.
      transparent = true,
      styles = {
        sidebars = 'transparent',
        floats = 'transparent',
      },
      -- NOTE: these are the exact standard solarized values, not the theme's palette,
      -- which uses slightly different shades — so naming them here shifts nothing
      -- visually while giving the highlights below one place to change.
      on_colors = function(c)
        c.bg_dark = 'NONE'
        c.sol_red = '#dc322f'
        c.sol_yellow = '#b58900'
        c.sol_blue = '#268bd2'
        c.sol_cyan = '#2aa198'
        c.muted = '#586e75'
        -- muted inline word-diff tints (gitsigns)
        c.gs_add = '#0f3a28'
        c.gs_change = '#3a3418'
        c.gs_delete = '#4a1f1f'
        c.gs_add_l = '#c7e6c7'
        c.gs_change_l = '#e8e0b0'
        c.gs_delete_l = '#e8c0c0'
      end,
      on_highlights = function(hl, c)
        local function is_dark()
          return vim.o.background == 'dark'
        end

        hl.WhichKey = {
          bg = 'NONE',
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

        hl.StatusLine = {
          bg = 'NONE',
        }
        hl.StatusLineNC = {
          bg = 'NONE',
        }

        hl.MacroRecording = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#dc322f',
          bold = true,
        }

        hl.ModifiedIndicator = {
          fg = '#dc322f',
          bg = 'NONE',
          bold = true,
        }

        hl.ReadonlyIndicator = {
          fg = '#cb4b16',
          bg = 'NONE',
          bold = true,
        }

        -- Diagnostics: coloured text only, no background.
        hl.DiagnosticError = { fg = c.sol_red, bg = 'NONE' }
        hl.DiagnosticVirtualTextError = { fg = c.sol_red, bg = 'NONE' }
        hl.DiagnosticUnderlineError = { sp = c.sol_red, underline = true }
        hl.DiagnosticSignError = { fg = c.sol_red, bg = 'NONE' }

        hl.DiagnosticWarn = { fg = c.sol_yellow, bg = 'NONE' }
        hl.DiagnosticVirtualTextWarn = { fg = c.sol_yellow, bg = 'NONE' }
        hl.DiagnosticUnderlineWarn = { sp = c.sol_yellow, underline = true }
        hl.DiagnosticSignWarn = { fg = c.sol_yellow, bg = 'NONE' }

        hl.DiagnosticInfo = { fg = c.sol_blue, bg = 'NONE' }
        hl.DiagnosticVirtualTextInfo = { fg = c.sol_blue, bg = 'NONE' }
        hl.DiagnosticUnderlineInfo = { sp = c.sol_blue, underline = true }
        hl.DiagnosticSignInfo = { fg = c.sol_blue, bg = 'NONE' }

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
        -- One accent per mode; the foreground inverts so it reads on both themes.
        hl.MiniStatuslineModeNormal = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#2aa198', -- cyan
          bold = true,
        }
        hl.MiniStatuslineModeInsert = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#dc322f', -- red
          bold = true,
        }
        hl.MiniStatuslineModeVisual = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#d33682', -- magenta
          bold = true,
        }
        hl.MiniStatuslineModeReplace = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#cb4b16', -- orange
          bold = true,
        }
        hl.MiniStatuslineModeCommand = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#b58900', -- yellow
          bold = true,
        }
        hl.MiniStatuslineMode = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#268bd2', -- blue
          bold = true,
        }

        hl.CursorLine = {
          bg = is_dark() and '#073642' or '#eee8d5', -- base02 / base2
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

        hl.Cursor = {
          fg = is_dark() and '#002B36' or '#FDF6E3', -- base03 / base3
          bg = '#2aa198',
        }
        hl.lCursor = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#2aa198',
        }
        hl.CursorIM = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#2aa198',
        }

        -- Matching bracket: inverted, so it is visible without hunting for it.
        hl.MatchParen = {
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bg = '#cb4b16',
          bold = true,
        }

        -- LSP occurrences: background only, no underline.
        hl.LspReferenceText = { bg = is_dark() and '#073642' or '#eee8d5' }
        hl.LspReferenceRead = { bg = is_dark() and '#073642' or '#eee8d5' }
        hl.LspReferenceWrite = { bg = is_dark() and '#073642' or '#eee8d5' }

        hl.Visual = {
          bg = is_dark() and '#073642' or '#93a1a1',
          fg = is_dark() and '#FDF6E3' or '#002B36',
          bold = true,
        }

        hl.Search = {
          bg = is_dark() and '#B58900' or '#CB4B16',
          fg = is_dark() and '#002B36' or '#FDF6E3',
          bold = true,
        }

        -- NOTE: transparent covers Normal/NormalNC/LineNr but not EndOfBuffer.
        hl.EndOfBuffer = { bg = 'NONE' }
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
        -- NOTE: inline word-diff is invisible on a transparent theme without an explicit
        -- background, hence the muted tints.
        hl.GitSignsAddLnInline = { bg = is_dark() and c.gs_add or c.gs_add_l }
        hl.GitSignsChangeLnInline = { bg = is_dark() and c.gs_change or c.gs_change_l }
        hl.GitSignsDeleteLnInline = { bg = is_dark() and c.gs_delete or c.gs_delete_l }
        -- NOTE: the theme paints additions teal, which reads as blue. This one override
        -- covers EVERY diff preview — the gitsigns float, :diffthis and snacks git
        -- previews all resolve to DiffAdd.
        hl.DiffAdd = { bg = is_dark() and c.gs_add or c.gs_add_l }
        -- current-line blame: muted italic, so it does not pull attention
        hl.GitSignsCurrentLineBlame = { fg = c.muted, italic = true }

        hl.SnacksDashboardHeader = { fg = '#dc322f', bold = true }
        hl.SnacksDashboardFooter = { fg = is_dark() and c.muted or '#93a1a1' }

        -- NOTE: indent guides default to linking against NonText and are nearly invisible.
        hl.SnacksIndent = { fg = is_dark() and '#3a4d52' or '#93a1a1' }
        hl.SnacksIndentScope = { fg = is_dark() and '#2aa198' or '#268bd2' }
        hl.SnacksIndent1 = { fg = '#268bd2' } -- blue
        hl.SnacksIndent2 = { fg = '#2aa198' } -- cyan
        hl.SnacksIndent3 = { fg = '#859900' } -- green
        hl.SnacksIndent4 = { fg = '#b58900' } -- yellow
        hl.SnacksIndent5 = { fg = '#cb4b16' } -- orange
        hl.SnacksIndent6 = { fg = '#d33682' } -- magenta

        hl.BlinkCmpMenu = { bg = 'NONE', fg = c.fg }
        hl.BlinkCmpMenuBorder = { bg = 'NONE', fg = c.muted }
        hl.BlinkCmpMenuSelection = { bg = is_dark() and '#073642' or '#eee8d5', bold = true }
        hl.BlinkCmpDoc = { bg = 'NONE', fg = c.fg }
        hl.BlinkCmpDocBorder = { bg = 'NONE', fg = c.muted }
        hl.BlinkCmpDocSeparator = { bg = 'NONE', fg = c.muted }
        hl.BlinkCmpSignatureHelp = { bg = 'NONE', fg = c.fg }
        hl.BlinkCmpSignatureHelpBorder = { bg = 'NONE', fg = c.muted }

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
        -- titles sitting on the border ("files" at the top) need a transparent background
        -- of their own, or they inherit the dark FloatTitle
        hl.SnacksPickerBorderTitle = { bg = 'NONE', fg = is_dark() and '#2aa198' or '#268bd2', bold = true }
        hl.SnacksPickerInputTitle = { bg = 'NONE', fg = is_dark() and '#2aa198' or '#268bd2', bold = true }
        hl.SnacksPickerListTitle = { bg = 'NONE', fg = is_dark() and '#2aa198' or '#268bd2', bold = true }
        hl.FloatTitle = { bg = 'NONE', fg = is_dark() and '#2aa198' or '#268bd2', bold = true }
        -- match highlighting in results: yellow, not the red Special it defaults to
        hl.SnacksPickerMatch = { fg = '#b58900', bold = true }
        -- NOTE: snacks links the selected row to Visual (bold, recoloured text, gray in
        -- light theme) — follow CursorLine instead, like the editor itself.
        hl.SnacksPickerListCursorLine = { bg = is_dark() and '#073642' or '#eee8d5' }
        hl.SnacksPickerPreviewCursorLine = { bg = is_dark() and '#073642' or '#eee8d5' }
        hl.SnacksPickerDir = { fg = c.muted }
        hl.BlinkCmpSignatureHelpActiveParameter = { fg = is_dark() and '#cb4b16' or '#dc322f', bold = true }
      end,
    }
  end,
  init = function()
    vim.cmd.colorscheme 'solarized-osaka'
    -- NOTE: manual `highlight … guibg=NONE` calls are not needed — transparent=true plus
    -- styles.floats/sidebars handle it inside the theme, and EndOfBuffer is covered above.
  end,
}
