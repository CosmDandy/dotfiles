-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons',
    'MunifTanjim/nui.nvim',
  },
  cmd = 'Neotree',
  keys = {
    { '\\', ':Neotree reveal<CR>', desc = 'NeoTree reveal', silent = true },
  },
  config = function()
    require("neo-tree").setup({
      filesystem = {
        filtered_items = {
          visible = true,          -- Показывать скрытые файлы
          hide_dotfiles = false,   -- Не скрывать .файлы
          hide_gitignored = false, -- Не скрывать файлы из .gitignore
        },
        window = {
          mappings = {
            ["\\"] = "close_window",
          },
        },
      },
    })
  end,
}
