-- Система автоформатирования для Python/SQL/DevOps разработчика
-- Этот файл заменит ваш nvim/lua/plugins/editor/autoformat.lua

return {
  'stevearc/conform.nvim',
  event = { 'BufWritePre' }, -- Загружаем перед сохранением для максимальной производительности
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>f',
      function()
        require('conform').format {
          async = true,
          lsp_format = 'prefer', -- Предпочитаем LSP форматирование когда доступно
          timeout_ms = 3000, -- Увеличенный таймаут для больших файлов
        }
      end,
      mode = '',
      desc = '[F]ormat buffer',
    },
    {
      '<leader>tf',
      function()
        -- Умное переключение автоформатирования с сохранением состояния
        if vim.g.conform_format_on_save == nil then
          vim.g.conform_format_on_save = true
        end

        if vim.g.conform_format_on_save then
          vim.g.conform_format_on_save = false
          require('conform').setup {
            format_on_save = false,
          }
          vim.notify('Автоформатирование при сохранении отключено', vim.log.levels.INFO)
        else
          vim.g.conform_format_on_save = true
          require('conform').setup {
            format_on_save = function(bufnr)
              -- Динамическое определение настроек форматирования
              return {
                timeout_ms = 3000,
                lsp_format = 'prefer',
              }
            end,
          }
          vim.notify('Автоформатирование при сохранении включено', vim.log.levels.INFO)
        end
      end,
      mode = '',
      desc = 'Toggle [F]ormat on save',
    },
  },
  opts = {
    notify_on_error = true, -- Уведомляем об ошибках форматирования
    notify_no_formatters = false, -- Не спамим если форматер не найден

    -- Основная функция автоформатирования при сохранении
    format_on_save = function(bufnr)
      -- Получаем информацию о файле для принятия решений
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      local filetype = vim.bo[bufnr].filetype

      -- Пропускаем форматирование для определенных типов файлов или больших файлов
      local disable_filetypes = {
        'sql', -- SQL форматируем вручную, так как структура может быть важна
        'text',
        'markdown', -- Markdown может иметь специфичное форматирование
      }

      -- Проверяем размер файла - не форматируем очень большие файлы автоматически
      local max_filesize = 100 * 1024 -- 100KB
      local ok, stats = pcall(vim.uv.fs_stat, bufname)
      if ok and stats and stats.size > max_filesize then
        vim.notify('Файл слишком большой для автоформатирования', vim.log.levels.WARN)
        return false
      end

      -- Отключаем для определенных типов файлов
      if vim.tbl_contains(disable_filetypes, filetype) then
        return false
      end

      -- Для Python проектов используем более строгие настройки
      if filetype == 'python' then
        return {
          timeout_ms = 5000, -- Больше времени для сложного Python кода
          lsp_format = 'prefer',
          quiet = false, -- Показываем что происходит
        }
      end

      -- Для конфигурационных файлов (YAML, JSON) форматируем быстро
      if vim.tbl_contains({ 'yaml', 'yml', 'json', 'dockerfile' }, filetype) then
        return {
          timeout_ms = 2000,
          lsp_format = 'prefer',
          quiet = true, -- Тихо для простых файлов
        }
      end

      -- Стандартные настройки для остальных файлов
      return {
        timeout_ms = 3000,
        lsp_format = 'prefer',
      }
    end,

    -- Конфигурация форматеров для каждого языка вашего стека
    formatters_by_ft = {
      -- Python - многоуровневая система форматирования
      python = function(bufnr)
        return { 'ruff_fix', 'black' }
      end,

      -- Lua - для конфигурации Neovim и скриптов
      lua = { 'stylua' },

      -- Web технологии - единый форматер для консистентности
      javascript = { 'prettierd' },
      typescript = { 'prettierd' },
      javascriptreact = { 'prettierd' },
      typescriptreact = { 'prettierd' },
      html = { 'prettierd' },
      css = { 'prettierd' },
      scss = { 'prettierd' },

      -- DevOps конфигурации - критично для правильной работы инфраструктуры
      yaml = { 'yamlfmt' },
      yml = { 'yamlfmt' },
      json = { 'prettierd' }, -- prettier лучше понимает JSON схемы

      -- Shell скрипты для автоматизации
      bash = { 'shfmt' },
      zsh = { 'shfmt' },
      sh = { 'shfmt' },

      -- XML файлы (Maven, конфигурации)
      xml = { 'xmlformatter' },

      -- HCL (Terraform/Nomad) - форматирование через LSP (terraform fmt)
      hcl = {},
      terraform = {},

      -- Dockerfile
      dockerfile = {}, -- Используем только LSP форматирование для Dockerfile
    },

    -- Детальная конфигурация каждого форматера
    formatters = {
      -- Python форматеры с оптимизированными настройками
      -- Конфигурация ruff для комплексного форматирования Python кода
      ruff_fix = {
        -- Применяем автоматические исправления и организацию импортов
        prepend_args = {
          'check', -- Режим проверки и исправления
          '--fix', -- Автоматически исправляем то, что можно исправить
          '--select',
          'I,F,E,W,UP,B', -- Выбираем правила: импорты, синтаксис, стиль, обновления, багфиксы
          '--ignore',
          'E501', -- Игнорируем длину строки (это сделает black)
          '--force-exclude', -- Принудительно исключаем файлы согласно конфигурации
        },
      },

      ruff_format = {
        -- Альтернативный подход: используем встроенное форматирование ruff
        prepend_args = {
          'format', -- Режим форматирования
          '--respect-gitignore', -- Уважаем .gitignore
        },
      },

      ruff_organize_imports = {
        -- Специализированная организация импортов
        prepend_args = {
          'check',
          '--fix',
          '--select',
          'I', -- Только правила импортов
          '--force-exclude',
        },
      },

      -- Обновленная конфигурация black для совместимости с ruff
      black = {
        prepend_args = {
          '--line-length',
          '88', -- Стандартная длина строки
          '--target-version',
          'py39', -- Поддержка современного Python
          '--fast', -- Быстрое форматирование
          '--quiet', -- Меньше вывода для чистоты
        },
      },

      -- YAML форматер для DevOps конфигураций
      yamlfmt = {
        prepend_args = {
          '-formatter',
          'indent=2,include_document_start=false,drop_merge_tag=true',
        },
      },

      -- Shell форматер
      shfmt = {
        prepend_args = {
          '-i',
          '2', -- Отступ в 2 пробела
          '-bn', -- Бинарные операторы в начале строки
          '-ci', -- Отступ для case в switch
          '-sr', -- Перенаправления после команд
        },
      },

      -- XML форматер
      xmlformatter = {
        prepend_args = {
          '--indent',
          '2',
          '--indent-char',
          ' ',
        },
      },
    },
  },

  -- Дополнительная конфигурация для интеграции с вашим workflow
  config = function(_, opts)
    require('conform').setup(opts)

    -- Создаем автокоманды для специфичных сценариев
    local conform_augroup = vim.api.nvim_create_augroup('python-devops-conform', { clear = true })

    -- Специальная обработка для YAML файлов в .github директории
    vim.api.nvim_create_autocmd('BufWritePre', {
      group = conform_augroup,
      pattern = '.github/**/*.yml',
      callback = function()
        -- Для GitHub Actions используем более строгое форматирование
        require('conform').format {
          formatters = { 'yamlfmt' },
          async = false, -- Синхронно для критических файлов
          timeout_ms = 5000,
        }
      end,
    })

    -- Создаем команду для форматирования всего проекта
    vim.api.nvim_create_user_command('FormatProject', function()
      local files =
        vim.fn.systemlist 'find . -type f \\( -name "*.py" -o -name "*.lua" -o -name "*.yml" -o -name "*.yaml" -o -name "*.json" \\) ! -path "./.git/*" ! -path "./venv/*" ! -path "./node_modules/*"'

      local formatted_count = 0
      for _, file in ipairs(files) do
        local buf = vim.fn.bufnr(file, false)
        if buf ~= -1 then
          require('conform').format {
            bufnr = buf,
            async = false,
          }
          formatted_count = formatted_count + 1
        end
      end

      vim.notify(string.format('Отформатировано %d файлов проекта', formatted_count), vim.log.levels.INFO)
    end, { desc = 'Format all project files' })
  end,
}
