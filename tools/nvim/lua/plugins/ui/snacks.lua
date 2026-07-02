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

-- select-окно без превью, по центру (preset 'select' прячет preview), 0.6×0.5; свежая таблица на вызов
local function select()
  return { layout = { preset = 'select', layout = { width = 0.6, height = 0.5 } } }
end

-- Исключения путей (как ignore_globs в telescope) для files/grep
local exclude = {
  '.git',
  'node_modules',
  '__pycache__',
  '*.pyc',
  '.venv',
  'venv',
  '*.min.js',
  '*.min.css',
  'var',
  '*.egg-info',
}
local function with_exclude(cfg)
  cfg.exclude = exclude
  return cfg
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
    -- рисовать файл сразу при открытии из шелла, до загрузки плагинов (без мелькания)
    quickfile = { enabled = true },
    -- плавающий vim.ui.input (rename и пр.) вместо строки внизу — в стиле остального snacks
    input = { enabled = true },
    -- подсветка вхождений символа под курсором (LSP document_highlight) + прыжки ]]/[[
    words = { enabled = true },
    -- текст-объекты по области: ii/ai + прыжки [i/]i
    scope = { enabled = true },
    -- Уведомления (заменили nvim-notify). style='compact' = с рамкой + иконкой/заголовком
    notifier = {
      enabled = true,
      timeout = 3000,
      style = 'compact',
      top_down = true,
    },
    styles = {
      notification = {
        border = 'rounded',
        wo = { winblend = 0 },
      },
      notification_history = {
        border = 'rounded',
        wo = { winblend = 0 },
      },
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
      -- frecency: часто и недавно открываемые файлы всплывают наверх
      matcher = { frecency = true },
      -- Пути короче и читаемее: сначала имя файла, потом каталог
      formatters = {
        file = {
          filename_first = true,
          truncate = 80,
        },
      },
      sources = {
        -- С превью снизу, ширина 0.9×0.9 (как telescope vertical)
        -- С превью снизу (60% превью / 40% список), 0.9×0.9 — как telescope vertical
        -- files/grep — с исключениями путей (node_modules, .venv, *.min.js и т.д.)
        files = with_exclude(vertical(0.6)),
        grep = with_exclude(vertical(0.6)),
        grep_buffers = with_exclude(vertical(0.6)),
        grep_word = with_exclude(vertical(0.6)),
        diagnostics = vertical(0.6),
        git_log = vertical(0.6),
        git_log_file = vertical(0.8),
        git_branches = vertical(0.6),
        -- marks — с превью (видно контекст метки), компактно по центру
        marks = { layout = { preset = 'dropdown' } },
        -- Без превью, по центру с рамкой (как telescope dropdown + previewer=false)
        -- preset 'select' имеет встроенное hidden={'preview'}
        buffers = select(),
        recent = select(),
        pickers = select(),
        keymaps = select(),
        search_history = select(),
        -- поиск по строкам буфера — превью снизу (длинные строки видны целиком)
        lines = vertical(0.6),
        -- :help — превью справа (текст статьи виден до прыжка)
        help = { layout = { preset = 'default' } },
        -- символы документа — список слева во всю высоту, превью кода справа.
        -- filter=true для конфиг-ФТ: их структуру LSP размечает как Object/Key/Variable,
        -- а дефолтный фильтр snacks эти типы прячет (оттого <leader>ds там пустой)
        lsp_symbols = {
          layout = { preset = 'default' },
          filter = {
            yaml = true,
            json = true,
            terraform = true,
            helm = true,
            dockerfile = true,
          },
        },
        -- символы воркспейса — вертикально: список во всю ширину, видны пути к файлам
        lsp_workspace_symbols = vertical(0.5),
        -- call hierarchy — код вызывающей/вызываемой функции в превью справа
        lsp_incoming_calls = { layout = { preset = 'default' } },
        lsp_outgoing_calls = { layout = { preset = 'default' } },
        -- git status/diff — превью диффа снизу (важнее списка файлов)
        git_status = vertical(0.6),
        git_diff = vertical(0.7),
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
