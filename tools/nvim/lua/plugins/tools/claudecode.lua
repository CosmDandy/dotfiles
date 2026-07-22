-- Claude Code запускается руками в своём пейне tmux, плагин его НЕ создаёт.
-- Провайдер ниже управляет только размещением этого пейна: команды плагина
-- перекидывают живую сессию между отдельным окном tmux и сплитом справа от
-- nvim (join-pane/break-pane). Процесс тот же, ws-соединение не рвётся.
local pane_script = vim.env.HOME .. '/.dotfiles/tools/tmux/claude-pane.sh'

local function pane(action)
  if not vim.env.TMUX or vim.fn.executable(pane_script) ~= 1 then
    return
  end
  local cmd = { pane_script, action }
  if vim.env.TMUX_PANE then
    -- окно nvim-пейна, а не активного: активным может быть уже сам claude
    table.insert(cmd, vim.env.TMUX_PANE)
  end
  vim.system(cmd)
end

local tmux_provider = {
  setup = function() end,
  -- focus == false приходит только из ensure_visible-пути плагина
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
  -- терминала внутри nvim нет: буфера не существует, ClaudeCodeSendText не работает
  get_active_bufnr = function()
    return nil
  end,
  -- Всегда true намеренно: вернуть false — значит уронить плагин в fallback на
  -- native-провайдер, который откроет ВТОРОЙ claude прямо в буфере nvim. Вне
  -- tmux провайдер просто ничего не делает, как прежний 'none'.
  is_available = function()
    return true
  end,
}

return {
  'coder/claudecode.nvim',
  -- VeryLazy, а не lazy=false: тот же eager-старт (auto_start=true поднимает WS-сервер
  -- и lock-файл ~/.claude/ide/ сразу после старта nvim, до любого нажатия клавиш —
  -- внешний claude в соседнем tmux-пейне подхватывает IDE-интеграцию так же), но
  -- вне синхронного пути запуска: полный набор keys ниже всё равно триггернул бы
  -- загрузку по первому нажатию, а VeryLazy просто убирает эти ~10мс из startuptime.
  event = 'VeryLazy',
  opts = {
    terminal = {
      provider = tmux_provider,
    },
    track_selection = true,
    -- отправил строку — фокус сразу в claude-пейне (он же подтягивается в сплит),
    -- вопрос дописывается там же; обратно в код — C-y
    focus_after_send = true,
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
