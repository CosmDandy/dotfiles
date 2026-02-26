-- Keymaps
local function map(mode, l, r, opts)
  opts = opts or {}
  vim.keymap.set(mode, l, r, opts)
end
-- [[Graphite Keymaps]]
-- map('n', 'y', 'h', { noremap = true, silent = true })
-- map('n', 'h', 'j', { noremap = true, silent = true })
-- map('n', 'a', 'k', { noremap = true, silent = true })
-- map('n', 'e', 'l', { noremap = true, silent = true })

-- Basic keymaps
map('n', '<Esc>', '<cmd>nohlsearch<CR>')
map('n', '<leader>q', vim.diagnostic.setloclist, { desc = '[Q]uickfix' })

map('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

map('n', '<C-y>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
map('n', '<C-e>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
map('n', '<C-h>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
map('n', '<C-a>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

map('n', '<leader>wd', '<cmd>delmarks!<CR>', { desc = '[D]elete marks', noremap = true, silent = true })

map("n", "<leader>du", ":DBUIToggle<CR>", { desc = "Toggle Dadbod UI" })
map("n", "<leader>da", ":DBUIAddConnection<CR>", { desc = "Add DB Connection" })

map('n', '<leader>cy', ':SetYamlSchema<CR>', { desc = 'Set [Y]AML schema', noremap = true, silent = true })
