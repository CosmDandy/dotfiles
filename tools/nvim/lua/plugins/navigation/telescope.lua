return { -- Fuzzy Finder (files, lsp, etc)
  'nvim-telescope/telescope.nvim',
  cmd = 'Telescope',
  keys = {
    { '<leader>s', desc = '[S]earch' },
    { '<leader>/', desc = 'Search in buffer' },
    { '<leader><leader>', desc = 'Buffers' },
  },
  -- Используем latest версию для совместимости с новым treesitter
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
        -- Оптимизация для больших проектов
        file_ignore_patterns = {
          'node_modules',
          '.git/',
          '__pycache__/',
          '%.pyc',
          '.venv/',
          'venv/',
          '%.min.js',
          '%.min.css',
          -- Odoo специфичные исключения
          '^odoo/', -- Исходники фреймворка Odoo (раскомментируйте если нужен поиск там)
          'var/', -- Логи и профилирование
          '%.egg%-info/',
          -- Если нужен поиск в vendor/target - закомментируйте эти строки
          -- 'vendor/',
          -- 'target/',
        },
        -- Ограничение результатов для предотвращения зависаний
        cache_picker = {
          num_pickers = 10,
        },
        -- Ripgrep аргументы для ускорения поиска
        vimgrep_arguments = {
          'rg',
          '--color=never',
          '--no-heading',
          '--with-filename',
          '--line-number',
          '--column',
          '--smart-case',
          '--hidden',
          '--glob=!.git/',
          '--max-columns=500', -- Обрезать длинные строки
          '--max-filesize=2M', -- Игнорить файлы больше 2MB
        },
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
          -- Показывать скрытые файлы, но игнорить .git
          hidden = true,
          find_command = { 'rg', '--files', '--hidden', '--glob', '!.git/' },
        },

        live_grep = {
          layout_strategy = 'vertical',
          layout_config = {
            width = 0.9,
            height = 0.9,
            preview_height = 0.6,
          },
          -- Ограничение результатов для предотвращения зависаний
          max_results = 500,
          -- Дополнительные аргументы для live_grep
          additional_args = function()
            return { '--hidden' }
          end,
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
    pcall(require('telescope').load_extension, 'fzf')
    pcall(require('telescope').load_extension, 'ui-select')

    -- [[Telescope Keymaps]]
    local builtin = require 'telescope.builtin'
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

    -- Grep по типу файлов
    vim.keymap.set('n', '<leader>sl', function()
      builtin.live_grep {
        type_filter = vim.fn.input 'File type: ',
      }
    end, { desc = 'Grep by [L]anguage' })

    -- Odoo специфичные маппинги
    vim.keymap.set('n', '<leader>sa', function()
      builtin.live_grep {
        search_dirs = { 'addons/' },
        prompt_title = 'Grep in Addons',
      }
    end, { desc = '[A]ddons only' })

    vim.keymap.set('n', '<leader>so', function()
      builtin.live_grep {
        search_dirs = { 'odoo/' },
        prompt_title = 'Grep in Odoo Core',
      }
    end, { desc = '[O]doo core only' })
  end,
}
