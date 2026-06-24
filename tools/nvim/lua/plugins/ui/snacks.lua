-- snacks.nvim — модульный набор утилит от folke
-- https://github.com/folke/snacks.nvim
-- Пока используем только модуль indent (замена indent-blankline)

-- vertical-окно с настраиваемой долей превью снизу (0.6 = превью 60% / список 40%)
-- возвращает свежую таблицу на каждый вызов — без общих ссылок
local function vertical(preview_ratio)
  return {
    layout = {
      layout = {
        box = 'vertical',
        width = 0.9,
        height = 0.9,
        border = true,
        title = '{title} {live} {flags}',
        title_pos = 'center',
        { win = 'input', height = 1, border = 'bottom' },
        { win = 'list', border = 'none' },
        { win = 'preview', title = '{preview}', height = preview_ratio, border = 'top' },
      },
    },
  }
end

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
    -- inline-рендер картинок не нужен и ломает treesitter на nvim 0.12 (метод range)
    image = { enabled = false },
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
      -- frecency: часто и недавно открываемые файлы всплывают наверх
      matcher = { frecency = true },
      -- Пути короче и читаемее: сначала имя файла, потом каталог
      formatters = {
        file = {
          filename_first = true,
          truncate = 60,
        },
      },
      sources = {
        -- С превью снизу, ширина 0.9×0.9 (как telescope vertical)
        -- С превью снизу (60% превью / 40% список), 0.9×0.9 — как telescope vertical
        files = vertical(0.6),
        grep = vertical(0.6),
        grep_buffers = vertical(0.6),
        grep_word = vertical(0.6),
        diagnostics = vertical(0.6),
        git_log = vertical(0.6),
        git_log_file = vertical(0.6),
        git_branches = vertical(0.6),
        -- marks — с превью (видно контекст метки), компактно по центру
        marks = { layout = { preset = 'dropdown' } },
        -- Без превью, по центру с рамкой (как telescope dropdown + previewer=false)
        -- preset 'select' имеет встроенное hidden={'preview'}
        buffers = { layout = { preset = 'select', layout = { width = 0.6, height = 0.5 } } },
        recent = { layout = { preset = 'select', layout = { width = 0.6, height = 0.5 } } },
        lines = { layout = { preset = 'select', layout = { width = 0.6, height = 0.5 } } },
        pickers = { layout = { preset = 'select', layout = { width = 0.6, height = 0.5 } } },
        keymaps = { layout = { preset = 'select', layout = { width = 0.6, height = 0.5 } } },
        search_history = { layout = { preset = 'select', layout = { width = 0.6, height = 0.5 } } },
        help = { layout = { preset = 'select', layout = { width = 0.6, height = 0.5 } } },
        lsp_symbols = { layout = { preset = 'select', layout = { width = 0.6, height = 0.5 } } },
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
