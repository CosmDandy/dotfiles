-- gitlinker.nvim — копирование permalink на текущую строку (GitHub/GitLab/Bitbucket)
-- https://github.com/linrongbin16/gitlinker.nvim
return {
  'linrongbin16/gitlinker.nvim',
  cmd = { 'GitLink' },
  keys = {
    { '<leader>gy', '<cmd>GitLink<cr>', mode = { 'n', 'v' }, desc = '[G]it [Y]ank link' },
    { '<leader>gY', '<cmd>GitLink!<cr>', mode = { 'n', 'v' }, desc = '[G]it open link in browser' },
  },
  opts = {},
}
