-- snacks.nvim — модульный набор утилит от folke
-- https://github.com/folke/snacks.nvim
-- Пока используем только модуль indent (замена indent-blankline)
return {
  'folke/snacks.nvim',
  priority = 1000,
  lazy = false,
  ---@type snacks.Config
  opts = {
    bigfile = {
      enabled = true,
      notify = true,
      size = 1.5 * 1024 * 1024, -- 1.5 MB
    },
    dashboard = {
      enabled = true,
      preset = {
        header = ' GO BIG OR GO HOME',
      },
      sections = {
        { section = 'header' },
        function()
          local stats = require('lazy').stats()
          return {
            align = 'center',
            padding = 1,
            text = { { ('◎ %dms'):format(math.floor(stats.startuptime + 0.5)), hl = 'SnacksDashboardFooter' } },
          }
        end,
      },
    },
    picker = {
      enabled = true,
      ui_select = true, -- заменяет vim.ui.select (вместо telescope-ui-select)
      sources = {
        -- файлы: классический вид с превью справа
        files = { layout = { preset = 'telescope' } },
        -- grep: снизу на всю ширину, удобно читать совпадения
        grep = { layout = { preset = 'ivy' } },
        grep_buffers = { layout = { preset = 'ivy' } },
        grep_word = { layout = { preset = 'ivy' } },
        diagnostics = { layout = { preset = 'ivy' } },
        -- компактные списки без тяжёлого превью: сверху по центру
        buffers = { layout = { preset = 'vscode' } },
        recent = { layout = { preset = 'vscode' } },
        -- системные списки: выпадашка по центру
        keymaps = { layout = { preset = 'dropdown' } },
        marks = { layout = { preset = 'dropdown' } },
        help = { layout = { preset = 'dropdown' } },
        search_history = { layout = { preset = 'dropdown' } },
        pickers = { layout = { preset = 'dropdown' } },
        lsp_symbols = { layout = { preset = 'dropdown' } },
        -- LSP-навигация и git остаются на дефолте (превью важно)
      },
    },
    indent = {
      enabled = true,
      indent = {
        char = '┊',
        hl = 'SnacksIndent',
      },
      scope = {
        enabled = true,
        char = '│',
        underline = false,
        hl = {
          'SnacksIndent1',
          'SnacksIndent2',
          'SnacksIndent3',
          'SnacksIndent4',
          'SnacksIndent5',
          'SnacksIndent6',
        },
      },
      chunk = { enabled = false },
      animate = { enabled = false },
      filter = function(buf)
        local ft = vim.bo[buf].filetype
        local excluded = {
          help = true,
          alpha = true,
          dashboard = true,
          lazy = true,
          mason = true,
          notify = true,
          Trouble = true,
          trouble = true,
          oil = true,
        }
        return vim.g.snacks_indent ~= false and vim.b[buf].snacks_indent ~= false and not excluded[ft]
      end,
    },
  },
}
