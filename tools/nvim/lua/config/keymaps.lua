-- Keymaps
local function map(mode, l, r, opts)
  opts = opts or {}
  vim.keymap.set(mode, l, r, opts)
end
-- Basic keymaps
map('n', '<Esc>', '<cmd>nohlsearch<CR>')

map('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- Split/pane navigation lives in plugins/navigation/tmux-navigator.lua — C-y/C-h/C-a/C-e
-- move seamlessly across both nvim splits and tmux panes.

map('n', '<leader>cy', ':SetYamlSchema<CR>', { desc = 'Set [Y]AML schema', noremap = true, silent = true })
