-- Перевод telescope-пикеров на snacks.picker (те же keymaps).
-- live_grep_args (sG/sW) и todo (st) остаются на telescope — см. telescope.lua
return {
  'folke/snacks.nvim',
  keys = {
    -- git
    { '<leader>gf', function() Snacks.picker.git_log_file() end, desc = '[f]ile history' },
    { '<leader>gh', function() Snacks.picker.git_log() end, desc = 'commits [h]istory' },
    { '<leader>gc', function() Snacks.picker.git_branches() end, desc = '[c]hange branches' },

    -- search
    { '<leader>sh', function() Snacks.picker.search_history() end, desc = '[h]istory' },
    { '<leader>sH', function() Snacks.picker.help() end, desc = '[H]elp' },
    { '<leader>sk', function() Snacks.picker.keymaps() end, desc = '[K]eymaps' },
    { '<leader>sf', function() Snacks.picker.files() end, desc = '[F]iles' },
    { '<leader>s?', function() Snacks.picker.pickers() end, desc = 'Pickers' },
    { '<leader>sw', function() Snacks.picker.grep_word() end, mode = { 'n', 'x' }, desc = '[W]ord' },
    { '<leader>sg', function() Snacks.picker.grep() end, desc = '[G]rep' },
    { '<leader>sd', function() Snacks.picker.diagnostics() end, desc = '[D]iagnostics' },
    { '<leader>sr', function() Snacks.picker.resume() end, desc = '[R]esume' },
    { '<leader>sm', function() Snacks.picker.marks() end, desc = '[M]arks' },
    { '<leader>s.', function() Snacks.picker.recent() end, desc = '[.] Recent Files' },
    { '<leader>sn', function() Snacks.picker.files { cwd = vim.fn.stdpath 'config' } end, desc = '[N]eovim files' },

    -- buffers / lines
    { '<leader><leader>', function() Snacks.picker.buffers() end, desc = '[ ] Buffers' },
    { '<leader>/', function() Snacks.picker.lines() end, desc = '[/] Search in buffer' },
    { '<leader>s/', function() Snacks.picker.grep_buffers() end, desc = '[/] in Open Files' },
  },
}
