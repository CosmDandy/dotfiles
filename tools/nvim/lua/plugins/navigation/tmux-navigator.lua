-- Seamless navigation between nvim splits and tmux panes with the same keys.
-- Layout: y/h/a/e = left/down/up/right, matching .tmux.conf.
return {
  'christoomey/vim-tmux-navigator',
  cmd = {
    'TmuxNavigateLeft',
    'TmuxNavigateDown',
    'TmuxNavigateUp',
    'TmuxNavigateRight',
  },
  init = function()
    vim.g.tmux_navigator_no_mappings = 1
  end,
  keys = {
    { '<C-y>', '<cmd>TmuxNavigateLeft<CR>', desc = 'Tmux/Win left' },
    { '<C-h>', '<cmd>TmuxNavigateDown<CR>', desc = 'Tmux/Win down' },
    { '<C-a>', '<cmd>TmuxNavigateUp<CR>', desc = 'Tmux/Win up' },
    { '<C-e>', '<cmd>TmuxNavigateRight<CR>', desc = 'Tmux/Win right' },
  },
}
