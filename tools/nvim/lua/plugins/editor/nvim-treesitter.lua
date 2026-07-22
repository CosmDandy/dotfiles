return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,
    build = ':TSUpdate',
    -- Queries текстовых объектов (функции/классы/блоки) — используются через mini.ai
    dependencies = {
      { 'nvim-treesitter/nvim-treesitter-textobjects', branch = 'main' },
    },
    config = function()
      local ts = require 'nvim-treesitter'

      -- Парсеры под DevOps-стек
      local ensure = {
        'python', 'sql', 'json', 'csv', 'bash', 'html', 'css', 'javascript',
        'diff', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'gitignore',
        'rust', 'dockerfile', 'yaml', 'hcl', 'terraform', 'jinja', 'toml',
        'xml', 'regex', 'vim', 'vimdoc', 'gotmpl', 'helm', 'jsonnet',
      }
      -- Установить недостающие парсеры (idempotent). В интерактивной сессии —
      -- асинхронно, чтобы не задерживать старт. В headless (сборка образа,
      -- активация home-manager) ждём завершения: иначе nvim выходит раньше
      -- компиляции и в образ попадает случайное подмножество парсеров.
      pcall(function()
        local handle = ts.install(ensure)
        if handle and #vim.api.nvim_list_uis() == 0 then
          handle:wait(600000)
        end
      end)

      -- ft → парсер там, где имена расходятся (иначе language.get_lang=nil → нет подсветки)
      pcall(vim.treesitter.language.register, 'jinja', { 'jinja2', 'htmldjango' })

      -- Нативная связка: подсветка и folds через vim.treesitter (ядро), индент — от плагина.
      -- Плагин остаётся ТОЛЬКО установщиком парсеров + источником queries: в ядре nvim 0.12
      -- всего 7 встроенных парсеров и нет установщика, поэтому полностью убрать его нельзя
      -- (оригинальный репо заархивирован 04.2026, но ветка main работает на 0.12).
      -- Инкрементальное выделение по дереву разбора: <C-space> расширяет
      -- выделение до следующего узла вверх, <BS> откатывает на шаг назад.
      -- Своя реализация, потому что модуль incremental_selection вырезан из
      -- nvim-treesitter вместе со старой системой модулей на ветке main, а
      -- штатной замены upstream не предложил.
      -- Стек хранится на буфер и сбрасывается при выходе из visual: без сброса
      -- следующее расширение продолжалось бы от узла прошлого выделения.
      local sel_stack = {}
      -- Флаг «мы сами меняем режим». Без него автокоманда ниже принимала выход
      -- из visual внутри select_range за выход пользователя и обнуляла стек:
      -- каждое второе расширение начиналось заново от курсора, выделение
      -- схлопывалось в точку вместо перехода к родителю.
      local ts_internal = false

      local function select_range(sr, sc, er, ec)
        -- диапазоны treesitter нуль-индексные, конец исключающий; visual —
        -- единично-индексный и включающий, отсюда пересчёт. ec == 0 значит,
        -- что узел кончается в самом начале строки er, то есть последний
        -- входящий символ — в конце предыдущей строки.
        if ec == 0 and er > 0 then
          er = er - 1
          ec = #vim.fn.getline(er + 1)
        end
        ts_internal = true
        if vim.fn.mode():match '[vV\22]' then
          vim.cmd 'normal! \27'
        end
        vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
        vim.cmd 'normal! v'
        vim.api.nvim_win_set_cursor(0, { er + 1, math.max(ec - 1, 0) })
        ts_internal = false
      end

      local function ts_expand()
        local buf = vim.api.nvim_get_current_buf()
        local st = sel_stack[buf]
        local node
        if not st or #st == 0 then
          st = {}
          sel_stack[buf] = st
          node = vim.treesitter.get_node()
        else
          -- поднимаемся, пока диапазон не изменится: у вложенных узлов он
          -- часто совпадает, и шаг выглядел бы как отсутствие реакции
          local prev = st[#st]
          node = prev
          repeat
            node = node:parent()
          until not node or not vim.deep_equal({ node:range() }, { prev:range() })
        end
        if not node then
          return
        end
        table.insert(st, node)
        select_range(node:range())
      end

      local function ts_shrink()
        local buf = vim.api.nvim_get_current_buf()
        local st = sel_stack[buf]
        if not st or #st < 2 then
          return
        end
        table.remove(st)
        select_range(st[#st]:range())
      end

      vim.keymap.set({ 'n', 'x' }, '<C-space>', ts_expand, { desc = 'Расширить выделение по дереву' })
      vim.keymap.set('x', '<BS>', ts_shrink, { desc = 'Сузить выделение по дереву' })

      vim.api.nvim_create_autocmd('ModeChanged', {
        group = vim.api.nvim_create_augroup('treesitter-incremental', { clear = true }),
        pattern = '[vV\22]*:[^vV\22]*',
        callback = function(args)
          if not ts_internal then
            sel_stack[args.buf] = nil
          end
        end,
      })

      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('treesitter-features', { clear = true }),
        callback = function(args)
          local buf = args.buf
          local ft = vim.bo[buf].filetype
          if ft == '' then
            return
          end
          local lang = vim.treesitter.language.get_lang(ft) or ft
          -- подсветка — только если парсер доступен (pcall защищает на первом запуске)
          if pcall(vim.treesitter.start, buf, lang) then
            -- folds — нативные (vim.treesitter.foldexpr), открыты по умолчанию (foldlevel 99).
            -- vim.wo[0][0] — оконно-локально-для-буфера, чтобы не утекало в другие окна.
            vim.wo[0][0].foldmethod = 'expr'
            vim.wo[0][0].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
            vim.wo[0][0].foldlevel = 99
            -- индентация от nvim-treesitter (помечена upstream как experimental)
            vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },
  {
    'nvim-treesitter/nvim-treesitter-context',
    cmd = { 'TSContextEnable', 'TSContextDisable', 'TSContextToggle' },
    keys = {
      {
        '<leader>tc',
        function()
          require('treesitter-context').toggle()
        end,
        desc = 'Toggle Treesitter Context',
      },
    },
    opts = {
      enable = false, -- по умолчанию выкл (дёргал вьюпорт при скролле); включается вручную <leader>tc
      max_lines = 3,
      multiline_threshold = 1,
      trim_scope = 'outer',
      mode = 'cursor',
    },
  },
}
