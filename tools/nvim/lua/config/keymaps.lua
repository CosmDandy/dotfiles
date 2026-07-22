-- Keymaps
local function map(mode, l, r, opts)
  opts = opts or {}
  vim.keymap.set(mode, l, r, opts)
end
-- Basic keymaps
map('n', '<Esc>', '<cmd>nohlsearch<CR>')

map('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- Навигация по сплитам/пейнам — см. plugins/navigation/tmux-navigator.lua
-- (C-y/C-h/C-a/C-e бесшовно прыгают и по nvim-сплитам, и по tmux-пейнам)

map('n', '<leader>cy', ':SetYamlSchema<CR>', { desc = 'Set [Y]AML schema', noremap = true, silent = true })
