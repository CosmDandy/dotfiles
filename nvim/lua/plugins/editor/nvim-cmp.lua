-- Autocompletion
--
-- For an understanding of why these mappings were
-- chosen, you will need to read `:help ins-completion`
--
-- No, but seriously. Please read `:help ins-completion`, it is really good!
return {
  'hrsh7th/nvim-cmp',
  event = 'InsertEnter',
  dependencies = {
    {
      'L3MON4D3/LuaSnip',
      event = 'InsertEnter',
      build = (function()
        return 'make install_jsregexp'
      end)(),
      dependencies = {
        {
          'rafamadriz/friendly-snippets',
          config = function()
            require('luasnip.loaders.from_vscode').lazy_load()
          end,
        },
      },
    },
    'saadparwaiz1/cmp_luasnip',
    'hrsh7th/cmp-nvim-lsp',
    'hrsh7th/cmp-path',
    'hrsh7th/cmp-buffer',
    'hrsh7th/cmp-cmdline',
    'hrsh7th/cmp-nvim-lsp-signature-help',
    -- 'windwp/nvim-ts-autotag',
    -- 'davidsierradz/cmp-conventionalcommits',
  },
  config = function()
    local cmp = require 'cmp'
    local luasnip = require 'luasnip'
    luasnip.config.setup {}

    cmp.setup {
      snippet = {
        expand = function(args)
          luasnip.lsp_expand(args.body)
        end,
      },
      completion = { completeopt = 'menu,menuone,preview' },

      mapping = cmp.mapping.preset.insert {
        -- Select the [n]ext item
        ['<C-n>'] = cmp.mapping.select_next_item(),
        -- Select the [p]revious item
        ['<C-p>'] = cmp.mapping.select_prev_item(),

        -- Scroll the documentation window [b]ack / [f]orward
        ['<C-b>'] = cmp.mapping.scroll_docs(-4),
        ['<C-f>'] = cmp.mapping.scroll_docs(4),

        -- Accept ([y]es) the completion.
        --  This will auto-import if your LSP supports it.
        --  This will expand snippets if the LSP sent a snippet.
        ['<Tab>'] = cmp.mapping.confirm { select = true },
        -- ['<C-y>'] = cmp.mapping.confirm { select = true },
        -- ['<CR>'] = cmp.mapping.confirm { select = true },
        -- ['<Tab>'] = cmp.mapping.select_next_item(),
        -- ['<S-Tab>'] = cmp.mapping.select_prev_item(),

        -- Manually trigger a completion from nvim-cmp.
        ['<C-Space>'] = cmp.mapping.complete {},

        -- <c-e> will move you to the right of each of the expansion locations.
        ['<C-e>'] = cmp.mapping(function()
          if luasnip.expand_or_locally_jumpable() then
            luasnip.expand_or_jump()
          end
        end, { 'i', 's' }),

        -- <c-y> is similar, except moving you backwards.
        ['<C-y>'] = cmp.mapping(function()
          if luasnip.locally_jumpable(-1) then
            luasnip.jump(-1)
          end
        end, { 'i', 's' }),

        -- Copilot accept
        ['<C-g>'] = cmp.mapping(function(fallback)
          vim.api.nvim_feedkeys(vim.fn['copilot#Accept'](vim.api.nvim_replace_termcodes('<Tab>', true, true, true)), 'n', true)
        end),
        -- For more advanced Luasnip keymaps (e.g. selecting choice nodes, expansion) see:
        --    https://github.com/L3MON4D3/LuaSnip?tab=readme-ov-file#keymaps
      },

      sources = cmp.config.sources({
        -- Группа 0: Высший приоритет для специализированных инструментов
        {
          name = 'lazydev', -- Для разработки Neovim конфигурации
          group_index = 0,
          priority = 1000,
          -- Активируется только в Lua файлах автоматически
        },

        -- Группа 1: Основные источники для программирования
        {
          name = 'nvim_lsp', -- Python LSP (pyright), SQL LSP, YAML LSP и др.
          group_index = 1,
          priority = 1000,
          keyword_length = 1, -- Быстрая активация для точной работы с Python API
          max_item_count = 50, -- Достаточно для детального выбора, но не перегружает
        },

        {
          name = 'vim-dadbod-completion', -- SQL автодополнение для работы с БД
          group_index = 1,
          priority = 950,
          keyword_length = 1, -- Важно для SQL - часто нужны предложения сразу
          -- Этот источник активируется только в SQL файлах благодаря конфигурации плагина
        },

        {
          name = 'nvim_lsp_signature_help', -- Подсказки сигнатур функций
          group_index = 1,
          priority = 900,
          -- Критично для Python - показывает параметры функций во время ввода
        },

        {
          name = 'luasnip', -- Сниппеты для быстрого написания кода
          group_index = 1,
          priority = 850,
          keyword_length = 2, -- Избегаем слишком раннего показа сниппетов
          max_item_count = 10, -- Ограничиваем для фокуса на наиболее релевантных
        },
      }, {
        -- Группа 2: Вспомогательные источники (показываются когда в первой группе недостаточно результатов)
        {
          name = 'path', -- Пути к файлам - критично для DevOps и Python импортов
          priority = 700,
          keyword_length = 2, -- Активируется при вводе ./ ../ / или названий директорий
          max_item_count = 15, -- Достаточно для навигации, но не загромождает
          option = {
            -- Оптимизируем для типичных DevOps путей
            trailing_slash = true, -- Добавляем слэш к директориям
            label_trailing_slash = true, -- Показываем слэш в метке
          },
        },

        {
          name = 'buffer', -- Содержимое открытых буферов
          priority = 600,
          keyword_length = 4, -- Повышенная длина - избегаем мусора из больших файлов
          max_item_count = 8, -- Небольшое количество для фокуса на релевантности
          option = {
            get_bufnrs = function()
              -- Только из видимых буферов для повышения релевантности
              local bufs = {}
              for _, win in ipairs(vim.api.nvim_list_wins()) do
                local buf = vim.api.nvim_win_get_buf(win)
                local buf_ft = vim.api.nvim_buf_get_option(buf, 'filetype')
                -- Исключаем специальные буферы, которые могут засорять автодополнение
                if buf_ft ~= 'help' and buf_ft ~= 'qf' and buf_ft ~= 'nofile' then
                  bufs[buf] = true
                end
              end
              return vim.tbl_keys(bufs)
            end,
          },
        },
      }, {
        -- Группа 3: Специализированные источники для определенных типов файлов
        {
          name = 'cmdline', -- Командная строка Vim - полезно для DevOps автоматизации
          priority = 500,
          keyword_length = 1,
          max_item_count = 5,
          m,
          -- Активируется автоматически в соответствующих контекстах
        },
      }),

      window = {
        completion = cmp.config.window.bordered {
          border = 'rounded', -- Округлые края
          scrollbar = false,
          col_offset = -3, -- Небольшой отступ слева
          side_padding = 1, -- Внутренние отступы
        },

        documentation = cmp.config.window.bordered {
          border = 'rounded',
          max_width = 80, -- Максимальная ширина документации
          max_height = 20, -- Максимальная высота
        },
      },

      -- Настройки форматирования элементов меню
      formatting = {
        fields = { 'kind', 'abbr', 'menu' }, -- Порядок отображения элементов
        format = function(entry, vim_item)
          -- Добавляем иконки для лучшего визуального восприятия
          local kind_icons = {
            Text = '󰉿',
            Method = '󰆧',
            Function = '󰊕',
            Constructor = '',
            Field = '󰜢',
            Variable = '󰀫',
            Class = '󰠱',
            Interface = '',
            Module = '',
            Property = '󰜢',
            Unit = '󰑭',
            Value = '󰎠',
            Enum = '',
            Keyword = '󰌋',
            Snippet = '',
            Color = '󰏘',
            File = '󰈙',
            Reference = '󰈇',
            Folder = '󰉋',
            EnumMember = '',
            Constant = '󰏿',
            Struct = '󰙅',
            Event = '',
            Operator = '󰆕',
            TypeParameter = '',
          }

          -- Устанавливаем иконку
          vim_item.kind = string.format('%s %s', kind_icons[vim_item.kind] or '', vim_item.kind)

          -- Показываем источник предложения
          vim_item.menu = ({
            nvim_lsp = '[LSP]',
            luasnip = '[Snippet]',
            buffer = '[Buffer]',
            path = '[Path]',
            lazydev = '[LazyDev]',
          })[entry.source.name]

          return vim_item
        end,
      },

      experimental = {
        ghost_text = true, -- Показывать предварительный текст
      },

      -- Производительность
      performance = {
        debounce = 60, -- Задержка перед показом меню (мс)
        throttle = 30, -- Задержка между обновлениями
        fetching_timeout = 500, -- Таймаут получения предложений
        confirm_resolve_timeout = 80, -- Таймаут разрешения при подтверждении
        async_budget = 1, -- Бюджет асинхронных операций (мс)
        max_view_entries = 200, -- Максимум видимых предложений
      },
    }
  end,
}
