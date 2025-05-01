return {
  'sindrets/diffview.nvim',
  enabled = false,
  cmd = { 'DiffviewOpen' },
  config = function()
    require('diffview').setup {}
  end,
  keys = {
    { '<leader>gd', '<cmd>DiffviewOpen<CR>' },
    { '<leader>gD', '<cmd>DiffviewClose<CR>' },
  },
}
