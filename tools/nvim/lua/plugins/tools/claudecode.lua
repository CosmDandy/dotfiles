-- Claude Code is started by hand in its own tmux pane; the plugin does NOT create it. The
-- provider below only manages where that pane lives — the plugin's commands move the live
-- session between a separate tmux window and a split beside nvim. Same process, and the ws
-- connection is never broken.
local pane_script = vim.env.HOME .. '/.dotfiles/tools/tmux/claude-pane.sh'

local function pane(action)
  if not vim.env.TMUX or vim.fn.executable(pane_script) ~= 1 then
    return
  end
  local cmd = { pane_script, action }
  if vim.env.TMUX_PANE then
    -- NOTE: the nvim pane's window, not the active one — the active pane may already be
    -- claude itself.
    table.insert(cmd, vim.env.TMUX_PANE)
  end
  vim.system(cmd)
end

local tmux_provider = {
  setup = function() end,
  -- focus == false only ever comes from the plugin's ensure_visible path
  open = function(_, _, _, focus)
    pane(focus == false and 'show' or 'focus')
  end,
  close = function()
    pane 'hide'
  end,
  simple_toggle = function()
    pane 'toggle'
  end,
  focus_toggle = function()
    pane 'focus_toggle'
  end,
  ensure_visible = function()
    pane 'show'
  end,
  -- there is no terminal inside nvim, so no buffer exists and ClaudeCodeSendText is out
  get_active_bufnr = function()
    return nil
  end,
  -- NOTE: always true on purpose — returning false drops the plugin into its native
  -- provider, which opens a SECOND claude right inside an nvim buffer. Outside tmux the
  -- provider simply does nothing, like the previous 'none'.
  is_available = function()
    return true
  end,
}

return {
  'coder/claudecode.nvim',
  -- NOTE: VeryLazy rather than lazy=false gives the same eager start (auto_start raises the
  -- WS server and the lock file right after nvim starts, so an external claude in the
  -- neighbouring pane still picks up the IDE integration) but off the synchronous startup
  -- path — the full keys spec below would trigger loading on the first press anyway.
  event = 'VeryLazy',
  opts = {
    terminal = {
      provider = tmux_provider,
    },
    track_selection = true,
    -- after sending a line the focus goes straight to the claude pane, which is pulled into
    -- the split; C-y comes back to the code
    focus_after_send = true,
    diff_opts = {
      layout = 'vertical',
      open_in_new_tab = false,
      keep_terminal_focus = false,
      -- rejecting a new file closes the placeholder window instead of leaving an empty buffer
      on_new_file_reject = 'close_window',
    },
  },
  keys = {
    { '<leader>a', nil, desc = 'AI/Claude Code' },
    { '<leader>am', '<cmd>ClaudeCodeSelectModel<cr>', desc = 'Select model' },
    { '<leader>ab', '<cmd>ClaudeCodeAdd %<cr>', desc = 'Add current buffer' },
    { '<leader>ac', '<cmd>ClaudeCode<cr>', desc = 'Toggle Claude pane in split' },
    { '<leader>af', '<cmd>ClaudeCodeFocus<cr>', desc = 'Focus Claude pane' },
    { '<leader>as', '<cmd>.ClaudeCodeSend<cr>', desc = 'Send current line' },
    { '<leader>as', '<cmd>ClaudeCodeSend<cr>', mode = 'v', desc = 'Send to Claude' },
    {
      '<leader>as',
      '<cmd>ClaudeCodeTreeAdd<cr>',
      desc = 'Add file',
      ft = 'oil',
    },
    { '<leader>aa', '<cmd>ClaudeCodeDiffAccept<cr>', desc = 'Accept diff' },
    { '<leader>ad', '<cmd>ClaudeCodeDiffDeny<cr>', desc = 'Deny diff' },
    { '<leader>aS', '<cmd>ClaudeCodeStatus<cr>', desc = 'Connection status' },
    { '<leader>ax', '<cmd>ClaudeCodeCloseAllDiffs<cr>', desc = 'Close all diffs' },
  },
}
