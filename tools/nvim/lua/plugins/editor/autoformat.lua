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
        vim.g.conform_format_on_save = not (vim.g.conform_format_on_save ~= false)
        local state = vim.g.conform_format_on_save and 'ON' or 'OFF'
        vim.notify('Format on save: ' .. state, vim.log.levels.INFO)
      end,
      mode = '',
      desc = 'Toggle [F]ormat on save',
    },
  },
  opts = {
    notify_on_error = true, -- Уведомляем об ошибках форматирования
    notify_no_formatters = false, -- Не спамим если форматер не найден

    format_on_save = function(bufnr)
      if vim.g.conform_format_on_save == false then
        return false
      end

      local bufname = vim.api.nvim_buf_get_name(bufnr)
      local filetype = vim.bo[bufnr].filetype

      local disable_filetypes = { 'sql', 'text', 'markdown' }
      if vim.tbl_contains(disable_filetypes, filetype) then
        return false
      end

      local max_filesize = 100 * 1024
      local ok, stats = pcall(vim.uv.fs_stat, bufname)
      if ok and stats and stats.size > max_filesize then
        return false
      end

      return {
        timeout_ms = 3000,
        lsp_format = 'prefer',
      }
    end,

    -- Конфигурация форматеров для каждого языка вашего стека
    formatters_by_ft = {
      -- Python: ruff fix (imports, lint fixes) → ruff format
      python = { 'ruff_fix', 'ruff_format' },

      -- Lua - для конфигурации Neovim и скриптов
      lua = { 'stylua' },

      -- DevOps конфигурации - критично для правильной работы инфраструктуры
      yaml = { 'yamlfmt' },
      yml = { 'yamlfmt' },

      -- Shell скрипты для автоматизации
      bash = { 'shfmt' },
      zsh = { 'shfmt' },
      sh = { 'shfmt' },

      -- HCL (Terraform/Nomad) - форматирование через LSP (terraform fmt)
      hcl = {},
      terraform = {},

      -- Dockerfile
      dockerfile = {}, -- Используем только LSP форматирование для Dockerfile

      -- Jsonnet
      jsonnet = { 'jsonnetfmt' },
    },

    -- Детальная конфигурация каждого форматера
    formatters = {
      -- Python форматеры с оптимизированными настройками
      -- Конфигурация ruff для комплексного форматирования Python кода
      ruff_fix = {
        prepend_args = {
          'check',
          '--fix',
          '--select',
          'I,F,E,W,UP,B',
          '--force-exclude',
        },
      },

      ruff_format = {
        prepend_args = {
          'format',
          '--line-length',
          '88',
          '--respect-gitignore',
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

    },
  },

}
