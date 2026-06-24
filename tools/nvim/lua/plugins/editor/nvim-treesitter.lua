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

      -- В main подсветка/индент включаются вручную через FileType (vim.treesitter — ядро)
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('treesitter-features', { clear = true }),
        callback = function(args)
          local buf = args.buf
          local ft = vim.bo[buf].filetype
          local lang = vim.treesitter.language.get_lang(ft) or ft
          -- подсветка — только если парсер доступен (pcall защищает на первом запуске)
          if pcall(vim.treesitter.start, buf, lang) then
            -- индентация от nvim-treesitter
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
      enable = false,
    },
  },
}
