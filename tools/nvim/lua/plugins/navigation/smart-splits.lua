-- Split resize mode on <C-w>R — the direct analogue of prefix+R in tmux. Enter it, press
-- y/h/a/e as many times as needed, Escape leaves. Same layout as navigation, but it moves
-- the border instead of the focus.
--
-- NOTE: a plugin rather than the built-in `vertical resize` because the vanilla commands
-- change the SIZE OF THE CURRENT WINDOW instead of moving a specific border — at the right
-- edge `<C-w><` moves the left one, which feels like pressing the wrong key. resize_left
-- moves the left border regardless of where the window sits, and behaves the same in a
-- grid mixing vertical and horizontal splits.
--
-- NOTE: multiplexer_integration carries the resize through into tmux once an nvim split
-- hits the edge; the plugin calls tmux over its CLI, so no extra bindings in .tmux.conf.
--
-- NOTE: the mode is a getcharstr loop, NOT a which-key hydra. which-key is disabled by
-- buftype (terminal/quickfix/help/nofile/prompt) and its popup never opens there, so the
-- mode would fall apart in exactly the windows one most wants to resize — verified in
-- :help, where the popup did not appear and the keys did not arrive.
--
-- NOTE: unlike tmux, an unbound key is returned to the buffer through feedkeys. The
-- symmetry is broken deliberately: in an editor a lost character costs more.
local DIRS = { y = 'left', h = 'down', a = 'up', e = 'right' }

local function resize_mode()
  local ss = require 'smart-splits'
  while true do
    vim.api.nvim_echo({ { 'RESIZE', 'WarningMsg' }, { '  y/h/a/e · Esc' } }, false, {})
    local ok, ch = pcall(vim.fn.getcharstr)
    vim.api.nvim_echo({ { '' } }, false, {})
    if not ok or ch == '\27' or ch == 'q' then
      return
    end
    local dir = DIRS[ch]
    if not dir then
      vim.api.nvim_feedkeys(ch, 'n', false)
      return
    end
    ss['resize_' .. dir]()
    vim.cmd.redraw()
  end
end

return {
  'mrjones2014/smart-splits.nvim',
  opts = { multiplexer_integration = 'tmux' },
  keys = {
    { '<C-w>R', resize_mode, desc = 'Resize mode' },
  },
}
