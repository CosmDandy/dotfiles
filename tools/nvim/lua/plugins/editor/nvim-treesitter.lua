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
      -- Установить недостающие парсеры (асинхронно, idempotent)
      pcall(function()
        ts.install(ensure)
      end)

      -- ft → парсер там, где имена расходятся (иначе language.get_lang=nil → нет подсветки)
      pcall(vim.treesitter.language.register, 'jinja', { 'jinja2', 'htmldjango' })

      -- Нативная связка: подсветка и folds через vim.treesitter (ядро), индент — от плагина.
      -- Плагин остаётся ТОЛЬКО установщиком парсеров + источником queries: в ядре nvim 0.12
      -- всего 7 встроенных парсеров и нет установщика, поэтому полностью убрать его нельзя
      -- (оригинальный репо заархивирован 04.2026, но ветка main работает на 0.12).
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
