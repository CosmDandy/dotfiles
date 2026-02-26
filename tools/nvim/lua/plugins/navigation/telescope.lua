local ignore_globs = {
  '--glob=!.git/',
  '--glob=!node_modules/',
  '--glob=!__pycache__/',
  '--glob=!*.pyc',
  '--glob=!.venv/',
  '--glob=!venv/',
  '--glob=!*.min.js',
  '--glob=!*.min.css',
  '--glob=!var/',
  '--glob=!*.egg-info/',
}

return { -- Fuzzy Finder (files, lsp, etc)
  'nvim-telescope/telescope.nvim',
  cmd = 'Telescope',
  keys = {
    { '<leader>s', desc = '[S]earch' },
    { '<leader>/', desc = 'Search in buffer' },
    { '<leader><leader>', desc = 'Buffers' },
  },
  branch = 'master',
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
    {
      'nvim-telescope/telescope-file-browser.nvim',
    },
    {
      'nvim-telescope/telescope-live-grep-args.nvim',
    },
  },
  config = function()
    local telescope = require 'telescope'
    local lga_actions = require 'telescope-live-grep-args.actions'

    telescope.setup {
      defaults = {
        path_display = { 'smart' },
        cache_picker = {
          num_pickers = 10,
        },
        vimgrep_arguments = vim.list_extend({
          'rg',
          '--color=never',
          '--no-heading',
          '--with-filename',
          '--line-number',
          '--column',
          '--smart-case',
          '--hidden',
          '--trim',
          '--max-columns=500',
          '--max-filesize=2M',
        }, ignore_globs),
      },
      extensions = {
        ['ui-select'] = {
          require('telescope.themes').get_dropdown(),
        },
        file_browser = {
          theme = 'ivy',
          hijack_netrw = true,
          mappings = {
            ['i'] = {},
            ['n'] = {},
          },
        },
        live_grep_args = {
          auto_quoting = true,
          mappings = {
            i = {
              ['<C-k>'] = lga_actions.quote_prompt(),
              ['<C-i>'] = lga_actions.quote_prompt { postfix = ' --iglob ' },
              ['<C-f>'] = require('telescope.actions').to_fuzzy_refine,
            },
          },
        },
      },
      pickers = {
        git_bcommits = {
          prompt_title = 'File history',
          theme = 'ivy',
          layout_config = {
            height = 0.6,
            preview_width = 0.6,
          },
          git_command = {
            'git',
            'log',
            '--pretty=%h %ad %s',
            '--date=short',
            '--follow',
            '--',
          },
        },

        git_commits = {
          layout_strategy = 'vertical',
          layout_config = {
            width = 0.9,
            height = 0.9,
            preview_height = 0.6,
          },
        },

        find_files = {
          layout_strategy = 'vertical',
          layout_config = {
            width = 0.9,
            height = 0.9,
            preview_height = 0.6,
          },
          hidden = true,
          find_command = vim.list_extend({
            'rg',
            '--files',
            '--hidden',
          }, ignore_globs),
        },

        live_grep = {
          layout_strategy = 'vertical',
          layout_config = {
            width = 0.9,
            height = 0.9,
            preview_height = 0.6,
          },
        },

        buffers = {
          theme = 'dropdown',
          previewer = false,
        },

        builtin = {
          theme = 'dropdown',
          previewer = false,
        },

        diagnostics = {
          layout_strategy = 'vertical',
          layout_config = {
            width = 0.9,
            height = 0.9,
            preview_height = 0.6,
          },
        },

        oldfiles = {
          theme = 'dropdown',
          previewer = false,
        },
      },
    }
    pcall(telescope.load_extension, 'fzf')
    pcall(telescope.load_extension, 'ui-select')
    pcall(telescope.load_extension, 'live_grep_args')

    -- [[Telescope Keymaps]]
    local builtin = require 'telescope.builtin'
    local lga_shortcuts = require 'telescope-live-grep-args.shortcuts'

    vim.keymap.set('n', '<leader>gf', builtin.git_bcommits, { desc = '[f]ile history' })
    vim.keymap.set('n', '<leader>gh', builtin.git_commits, { desc = 'commits [h]istory' })
    vim.keymap.set('n', '<leader>gc', builtin.git_branches, { desc = '[c]hange branches' })
    vim.keymap.set('n', '<leader>sh', builtin.search_history, { desc = '[h]istory' })
    vim.keymap.set('n', '<leader>sH', builtin.help_tags, { desc = '[H]elp' })
    vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[K]eymaps' })
    vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[F]iles' })
    vim.keymap.set('n', '<leader>s?', builtin.builtin, { desc = 'Telescope' })
    vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[W]ord' })
    vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[G]rep' })
    vim.keymap.set('n', '<leader>sG', telescope.extensions.live_grep_args.live_grep_args, { desc = '[G]rep with args' })
    vim.keymap.set('n', '<leader>sW', lga_shortcuts.grep_word_under_cursor, { desc = '[W]ord with args' })
    vim.keymap.set('v', '<leader>sW', lga_shortcuts.grep_visual_selection, { desc = '[W]ord with args' })
    vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[D]iagnostics' })
    vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[R]esume' })
    vim.keymap.set('n', '<leader>sm', builtin.marks, { desc = '[M]arks' })
    vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[.] Recent Files' })
    vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Buffers' })
    vim.keymap.set('n', '<leader>st', '<cmd>TodoTelescope<CR>', {
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

    vim.keymap.set('n', '<leader>s/', function()
      builtin.live_grep {
        grep_open_files = true,
        prompt_title = 'Grep in Open Files',
      }
    end, { desc = '[/] in Open Files' })

    vim.keymap.set('n', '<leader>sn', function()
      builtin.find_files { cwd = vim.fn.stdpath 'config' }
    end, { desc = '[N]eovim files' })
  end,
}
