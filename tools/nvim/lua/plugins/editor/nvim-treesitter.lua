return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'master',
    lazy = false,
    build = ':TSUpdate',
    main = 'nvim-treesitter.configs',
    -- Queries для текстовых объектов функций/классов/блоков (используются через mini.ai)
    dependencies = {
      { 'nvim-treesitter/nvim-treesitter-textobjects', branch = 'master' },
    },
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
        'markdown',
        'markdown_inline',
        'gitignore',
        'rust',
        'dockerfile',
        'yaml',
        'hcl',
        'terraform',
        'jinja',
        'toml',
        'xml',
        'regex',
        'vim',
        'gotmpl',
        'helm',
        'jsonnet',
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
