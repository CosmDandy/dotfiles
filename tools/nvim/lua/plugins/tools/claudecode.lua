return {
  'coder/claudecode.nvim',
  lazy = false,
  opts = {
    terminal = {
      provider = 'none',
    },
    track_selection = true,
    diff_opts = {
      layout = 'vertical',
      open_in_new_tab = false,
      keep_terminal_focus = false,
      -- при отказе от нового файла закрыть плейсхолдер-окно, не оставлять пустой буфер
      on_new_file_reject = 'close_window',
    },
  },
  keys = {
    { '<leader>a', nil, desc = 'AI/Claude Code' },
    { '<leader>am', '<cmd>ClaudeCodeSelectModel<cr>', desc = 'Select model' },
    { '<leader>ab', '<cmd>ClaudeCodeAdd %<cr>', desc = 'Add current buffer' },
    { '<leader>as', '<cmd>ClaudeCodeSend<cr>', mode = 'v', desc = 'Send to Claude' },
    {
      '<leader>as',
      '<cmd>ClaudeCodeTreeAdd<cr>',
      desc = 'Add file',
      ft = { 'NvimTree', 'neo-tree', 'oil', 'minifiles' },
    },
    { '<leader>aa', '<cmd>ClaudeCodeDiffAccept<cr>', desc = 'Accept diff' },
    { '<leader>ad', '<cmd>ClaudeCodeDiffDeny<cr>', desc = 'Deny diff' },
    { '<leader>aS', '<cmd>ClaudeCodeStatus<cr>', desc = 'Connection status' },
    { '<leader>ax', '<cmd>ClaudeCodeCloseAllDiffs<cr>', desc = 'Close all diffs' },
  },
}
