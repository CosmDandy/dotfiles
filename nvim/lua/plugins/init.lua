local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
  if vim.v.shell_error ~= 0 then
    error('Error cloning lazy.nvim:\n' .. out)
  end
end ---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

-- [[ Configure and install plugins ]]
require('lazy').setup({
  { 'tpope/vim-sleuth' },
  { "MTDL9/vim-log-highlighting" },
  -- Визуал
  { import = 'plugins.colorscheme' },
  { import = 'plugins.mini' },
  -- { import = 'plugins.lualine' },
  -- { import = 'plugins.indent_line' }, -- TODO:
  { import = 'plugins.autopairs' }, -- TODO:
  { import = 'plugins.oil' },
  { import = 'plugins.codewindow' },
  { import = 'plugins.barbecue' },
  { import = 'plugins.todo-comments' },
  { import = 'plugins.comments' },
  -- Уведомления
  { import = 'plugins.noice' }, -- TODO:
  -- Поиск и перемещение
  { import = 'plugins.telescope' },
  { import = 'plugins.flash' }, -- TODO:
  { import = 'plugins.grug' },  -- TODO:
  -- Подсказки с хоткеями
  { import = 'plugins.which-key' },
  -- LSP
  { import = 'plugins.lsp.nvim-treesitter' },
  { import = 'plugins.lsp.lsp' },        -- TODO:
  { import = 'plugins.lsp.lint' },       -- TODO:
  { import = 'plugins.lsp.autoformat' }, -- TODO:
  { import = 'plugins.lsp.nvim-cmp' },   -- TODO:
  { import = 'plugins.debug' },          -- TODO:
  -- Git
  { import = 'plugins.git' },
  -- Другое
  { import = 'plugins.toggleterm' }, -- TODO:
  -- { import = 'plugins.obsidian' }, -- TODO:
})

-- vim: ts=2 sts=2 sw=2 et
