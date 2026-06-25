-- Все пикеры на snacks.picker (telescope удалён полностью)
return {
  'folke/snacks.nvim',
  keys = {
    -- git
    { '<leader>gf', function() Snacks.picker.git_log_file() end, desc = '[f]ile history' },
    { '<leader>gh', function() Snacks.picker.git_log() end, desc = 'commits [h]istory' },
    { '<leader>gc', function() Snacks.picker.git_branches() end, desc = '[c]hange branches' },
    { '<leader>gw', function() Snacks.picker.git_status() end, desc = 'git status ([w]orking tree)' },
    { '<leader>gx', function() Snacks.picker.git_diff() end, desc = 'git diff hunks' },
    { '<leader>gz', function() Snacks.picker.git_stash() end, desc = 'git stash' },
    { '<leader>st', function() Snacks.picker.todo_comments() end, desc = '[t]odo' },

    -- search
    { '<leader>sh', function() Snacks.picker.search_history() end, desc = '[h]istory' },
    { '<leader>sH', function() Snacks.picker.help() end, desc = '[H]elp' },
    { '<leader>sk', function() Snacks.picker.keymaps() end, desc = '[K]eymaps' },
    { '<leader>sf', function() Snacks.picker.files() end, desc = '[F]iles' },
    { '<leader>s?', function() Snacks.picker.pickers() end, desc = 'Pickers' },
    { '<leader>sw', function() Snacks.picker.grep_word() end, mode = { 'n', 'x' }, desc = '[W]ord' },
    { '<leader>sg', function() Snacks.picker.grep() end, desc = '[G]rep' },
    { '<leader>sd', function() Snacks.picker.diagnostics() end, desc = '[D]iagnostics' },
    { '<leader>sl', function() Snacks.picker.lsp_config() end, desc = '[L]SP config' },

    -- прыжки по вхождениям символа под курсором (snacks.words)
    { ']]', function() Snacks.words.jump(1, true) end, desc = 'Next reference' },
    { '[[', function() Snacks.words.jump(-1, true) end, desc = 'Prev reference' },
    { '<leader>sr', function() Snacks.picker.resume() end, desc = '[R]esume' },
    { '<leader>sm', function() Snacks.picker.marks() end, desc = '[M]arks' },
    { '<leader>s.', function() Snacks.picker.recent() end, desc = '[.] Recent Files' },
    { '<leader>sn', function() Snacks.picker.files { cwd = vim.fn.stdpath 'config' } end, desc = '[N]eovim files' },

    -- buffers / lines
    { '<leader><leader>', function() Snacks.picker.buffers() end, desc = '[ ] Buffers' },
    { '<leader>/', function() Snacks.picker.lines() end, desc = '[/] Search in buffer' },
    { '<leader>s/', function() Snacks.picker.grep_buffers() end, desc = '[/] in Open Files' },

    -- Эксклюзивы snacks (нет аналога в telescope)
    { '<leader>ss', function() Snacks.picker.smart() end, desc = '[S]mart open (frecency)' },
    { '<leader>su', function() Snacks.picker.undo() end, desc = '[U]ndo history' },
    { '<leader>gl', function() Snacks.picker.git_log_line() end, desc = '[l]ine history (blame)' },
    { '<leader>sc', function() Snacks.picker.lsp_incoming_calls() end, desc = '[c]alls incoming' },
    { '<leader>sC', function() Snacks.picker.lsp_outgoing_calls() end, desc = '[C]alls outgoing' },
    { '<leader>E', function() Snacks.picker.explorer() end, desc = '[E]xplorer' },
    { '<leader>sR', function() Snacks.picker.registers() end, desc = '[R]egisters' },

    -- notifications (snacks.notifier — заменил :Noice history/dismiss)
    { '<leader>nh', function() Snacks.notifier.show_history() end, desc = 'Notification [h]istory' },
    { '<leader>nd', function() Snacks.notifier.hide() end, desc = '[d]ismiss notifications' },
  },
}
