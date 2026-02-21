return {
  {
    'tpope/vim-dadbod',
    lazy = true,
    cmd = 'DB', -- Загружается только по команде :DB
  },
  {
    'kristijanhusak/vim-dadbod-ui',
    dependencies = { 'tpope/vim-dadbod' },
    cmd = { 'DBUI', 'DBUIToggle', 'DBUIAddConnection', 'DBUIFindBuffer' }, -- Только по команде
    init = function()
      -- Не открывать help-таб при запуске
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_auto_execute_table_helpers = 1
    end,
  },
  {
    'kristijanhusak/vim-dadbod-completion',
    ft = { 'sql', 'mysql', 'plsql' }, -- Загружается только для SQL файлов
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
