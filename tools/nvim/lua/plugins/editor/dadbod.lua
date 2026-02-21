return {
  {
    'tpope/vim-dadbod',
    lazy = true,
    event = 'VeryLazy',
  },
  {
    'kristijanhusak/vim-dadbod-ui',
    event = 'VeryLazy',
    dependencies = { 'tpope/vim-dadbod' },
    cmd = { 'DBUI', 'DBUIToggle', 'DBUIAddConnection', 'DBUIFindBuffer' },
    init = function()
      -- Не открывать help-таб при запуске
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_auto_execute_table_helpers = 1
    end,
  },
  {
    'kristijanhusak/vim-dadbod-completion',
    event = 'VeryLazy',
    ft = { 'sql', 'mysql', 'plsql' },
    dependencies = { 'hrsh7th/nvim-cmp' },
    config = function()
      -- Включаем cmp-dadbod
      require('cmp').setup.filetype({ 'sql' }, {
        sources = {
          { name = 'vim-dadbod-completion' },
          { name = 'buffer' },
        },
      })
    end,
  },
}
