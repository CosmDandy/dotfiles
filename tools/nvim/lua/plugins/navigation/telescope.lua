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
    -- На telescope остаётся только то, что snacks.picker не заменяет
    { '<leader>sG', desc = '[G]rep with args' },
    { '<leader>sW', mode = { 'n', 'v' }, desc = '[W]ord with args' },
    { '<leader>st', desc = '[T]odo' },
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
        preview = {
          filesize_limit = 1, -- МБ: большие файлы не превьюим
          timeout = 200, -- мс на отрисовку превью, иначе бросаем
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
          find_command = { 'fd', '--type', 'f', '--hidden', '--strip-cwd-prefix', '--exclude', '.git', '--exclude', 'node_modules', '--exclude', '__pycache__', '--exclude', '.venv', '--exclude', 'venv' },
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
    pcall(telescope.load_extension, 'live_grep_args')

    -- Только live_grep_args остаётся на telescope (snacks.picker его не заменяет),
    -- и todo — остальное переехало в snacks-picker.lua
    local lga_shortcuts = require 'telescope-live-grep-args.shortcuts'
    vim.keymap.set('n', '<leader>sG', telescope.extensions.live_grep_args.live_grep_args, { desc = '[G]rep with args' })
    vim.keymap.set('n', '<leader>sW', lga_shortcuts.grep_word_under_cursor, { desc = '[W]ord with args' })
    vim.keymap.set('v', '<leader>sW', lga_shortcuts.grep_visual_selection, { desc = '[W]ord with args' })
    vim.keymap.set('n', '<leader>st', '<cmd>TodoTelescope<CR>', { desc = '[T]odo', noremap = true, silent = true })
  end,
}
