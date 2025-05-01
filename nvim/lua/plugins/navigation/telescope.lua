return { -- Fuzzy Finder (files, lsp, etc)
  'nvim-telescope/telescope.nvim',
  event = 'VimEnter',
  branch = '0.1.x',
  dependencies = {
    'nvim-lua/plenary.nvim',
    {
      'nvim-telescope/telescope-fzf-native.nvim',
      build = 'make',
      cond = function()
        return vim.fn.executable 'make' == 1
      end,
    },
    {
      'nvim-telescope/telescope-ui-select.nvim',
    },
    -- {
    --   'nvim-tree/nvim-web-devicons',
    --   enabled = vim.g.have_nerd_font,
    -- },
    {
      'nvim-telescope/telescope-file-browser.nvim',
    },
  },
  config = function()
    require('telescope').setup {
      defaults = {
        path_display = { 'smart' },
      },
      extensions = {
        -- TODO: разобраться с файловым менеджером
        ['ui-select'] = {
          require('telescope.themes').get_dropdown(),
        },
        file_browser = {
          theme = 'ivy',
          -- disables netrw and use telescope-file-browser in its place
          hijack_netrw = true,
          mappings = {
            ['i'] = {
              -- your custom insert mode mappings
            },
            ['n'] = {
              -- your custom normal mode mappings
            },
          },
        },
      },
    }
    pcall(require('telescope').load_extension, 'fzf')
    pcall(require('telescope').load_extension, 'ui-select')

    -- [[Telescope Keymaps]]
    local builtin = require 'telescope.builtin'
    vim.keymap.set('n', '<leader>sh', builtin.search_history, { desc = '[h]istory' })
    vim.keymap.set('n', '<leader>sH', builtin.help_tags, { desc = '[H]elp' })
    vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[K]eymaps' })
    vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[F]iles' })
    vim.keymap.set('n', '<leader>s?', builtin.builtin, { desc = 'Telescope' })
    vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[W]ord' })
    vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[G]rep' })
    vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[D]iagnostics' })
    vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[R]esume' })
    vim.keymap.set('n', '<leader>sm', builtin.marks, { desc = '[M]arks' })
    vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[.] Recent Files' })
    vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Buffers' })
    vim.keymap.set('n', '<leader>st', '<cmd>TodoTelescope keywords=TODO,FIX<CR>', {
      desc = '[T]odo',
      noremap = true,
      silent = true,
    })

    vim.keymap.set('n', '<leader>/', function()
      builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
        winblend = 10,
        previewer = false,
      })
    end, { desc = '[/] Search' })

    -- Поиск по открытым файлам
    vim.keymap.set('n', '<leader>s/', function()
      builtin.live_grep {
        grep_open_files = true,
        prompt_title = 'Grep in Open Files',
      }
    end, { desc = '[/] in Open Files' })

    -- Shortcut for searching your Neovim configuration files
    vim.keymap.set('n', '<leader>sn', function()
      builtin.find_files { cwd = vim.fn.stdpath 'config' }
    end, { desc = '[N]eovim files' })
  end,
}
