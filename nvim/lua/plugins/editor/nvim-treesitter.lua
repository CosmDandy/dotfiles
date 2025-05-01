return {
  {
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    main = 'nvim-treesitter.configs',
    -- [[ Configure Treesitter ]] See `:help nvim-treesitter`
    opts = {
      ensure_installed = {
        'python',
        'sql',
        'json',
        'csv',
        'bash',
        'html',
        'css',
        'javascript',
        'diff',
        'lua',
        'luadoc',
        'markdown',
        'markdown_inline',
        'gitignore',
        'rust',
        'query',
        'dockerfile',
        'yaml',
        'toml',
        'xml',
        'graphql',
        'regex',
        'vim',
        'vimdoc',
      },
      auto_install = true,
      highlight = {
        enable = true,
      },
      indent = {
        enable = true,
      },
      incremental_selection = {
        enable = true,
        keymaps = {
          init_selection = 'gnn',
          node_incremental = 'grn',
          scope_incremental = 'grc',
          node_decremental = 'grm',
        },
      },
    },
  },
  {
    'nvim-treesitter/nvim-treesitter-context',
    config = function()
      local context = require 'treesitter-context'
      context.setup {
        enable = false,
        -- max_lines = 8,
      }

      -- Хоткей для включения/выключения
      vim.keymap.set('n', '<leader>tc', function()
        context.toggle()
      end, { desc = 'Toggle Treesitter Context' })
    end,

    -- TODO: Добавить включение и выключение и хоткеи
    -- https://github.com/nvim-treesitter/nvim-treesitter-context?tab=readme-ov-file
  },
}
