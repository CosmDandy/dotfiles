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
    {
      'nvim-tree/nvim-web-devicons',
      enabled = vim.g.have_nerd_font,
    },
    {
      'nvim-telescope/telescope-file-browser.nvim',
    },
  },
  config = function()
    local telescope = require('telescope')
    local actions = require('telescope.actions')
    local action_state = require('telescope.actions.state')

    require('telescope').setup {
      defaults = {
        path_display = { 'smart' },
        file_ignore_patterns = {
          -- Python специфичные исключения
          '__pycache__/',
          '%.pyc$',
          '%.pyo$',
          '%.pyd$',
          '.Python',
          'pip-log%.txt',
          'pip-delete-this-directory%.txt',
          '%.egg%-info/',
          '%.egg/',
          -- Виртуальные окружения
          'venv/',
          '.venv/',
          'env/',
          '.env/',
          'virtualenv/',
          -- Node.js для fullstack проектов
          'node_modules/',
          'package%-lock%.json',
          -- DevOps артефакты
          '%.terraform/',
          'terraform%.tfstate',
          'terraform%.tfstate%.backup',
          -- IDE и редакторы
          '%.vscode/',
          '%.idea/',
          '%.DS_Store',
          -- Git
          '%.git/',
          -- Логи и временные файлы
          '%.log$',
          '%.tmp$',
          '%.temp$',
        },

        -- Сортировка результатов с пониманием приоритетов разработчика
        cache_picker = {
          num_pickers = 10, -- Кешируем последние 10 поисков для быстрого доступа
        },
        pickers = {
          find_files = {
            hidden = true,
            find_command = {
              'fd',
              '--type', 'f',
              '--strip-cwd-prefix',
              '--exclude', '__pycache__',
              '--exclude', '.git',
              '--exclude', 'node_modules',
              '--exclude', 'venv',
              '--exclude', '.venv',
            },
          },
          live_grep = {
            additional_args = function()
              return {
                '--smart-case',             -- Умная чувствительность к регистру
                '--hidden',                 -- Поиск в скрытых файлах (конфигурации)
                '--glob', '!.git/*',        -- Исключаем .git
                '--glob', '!__pycache__/*', -- Исключаем Python кеш
                '--glob', '!venv/*',        -- Исключаем виртуальные окруженя
                '--glob', '!.venv/*',
                '--glob', '!node_modules/*',
              }
            end,
          },
        },
        sorting_strategy = 'ascending',
        layout_strategy = 'horizontal',
        layout_config = {
          horizontal = {
            prompt_position = 'top',
            preview_width = 0.6, -- Больше места для предварительного просмотра кода
            results_width = 0.4,
          },
          vertical = {
            mirror = false,
          },
          width = 0.90, -- Используем почти весь экран для эффективности
          height = 0.85,
          preview_cutoff = 120,
        },

        mappings = {
          i = {
            ['<C-j>'] = actions.move_selection_next,
            ['<C-k>'] = actions.move_selection_previous,
            ['<C-q>'] = actions.send_to_qflist + actions.open_qflist,
            ['<C-s>'] = actions.send_selected_to_qflist + actions.open_qflist,
            ['<C-h>'] = actions.which_key,         -- Показать доступные действия
            ['<CR>'] = smart_open_file,            -- Используем нашу умную функцию открытия

            ['<C-t>'] = actions.select_tab,        -- Открыть в новой вкладке
            ['<C-v>'] = actions.select_vertical,   -- Вертикальный сплит
            ['<C-x>'] = actions.select_horizontal, -- Горизонтальный сплит

            ['<C-u>'] = actions.preview_scrolling_up,
            ['<C-d>'] = actions.preview_scrolling_down,
          },

          n = {
            ['q'] = actions.close,
            ['<CR>'] = smart_open_file,
            ['<C-q>'] = actions.send_to_qflist + actions.open_qflist,
            ['<C-s>'] = actions.send_selected_to_qflist + actions.open_qflist,
            ['gg'] = actions.move_to_top,
            ['G'] = actions.move_to_bottom,
          },
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
    }
    pcall(require('telescope').load_extension, 'fzf')
    pcall(require('telescope').load_extension, 'ui-select')


    -- [[Telescope Keymaps]]
    local builtin = require 'telescope.builtin'
    vim.keymap.set('n', '<leader>s/', builtin.search_history, { desc = '[h]istory' })
    vim.keymap.set('n', '<leader>sH', builtin.help_tags, { desc = '[H]elp' })
    vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[k]eymaps' })
    vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[f]iles' })
    vim.keymap.set('n', '<leader>s?', builtin.builtin, { desc = 'Telescope' })
    vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[w]ord' })
    vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[g]rep' })
    vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[d]iagnostics' })
    vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[r]esume' })
    vim.keymap.set('n', '<leader>sm', builtin.marks, { desc = '[m]arks' })
    vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[.] Recent Files' })
    vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Buffers' })
    vim.keymap.set('n', '<leader>st', '<cmd>TodoTelescope keywords=TODO,FIX<CR>', {
      desc = '[T]odo',
      noremap = true,
      silent = true,
    })

    vim.keymap.set('n', '<leader>/', function()
      builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
        previewer = false,
      })
    end, { desc = '[/] Search' })

    -- Поиск по открытым файлам
    vim.keymap.set('n', '<leader>sG', function()
      builtin.live_grep {
        grep_open_files = true,
        prompt_title = '[G]rep in Open Files',
      }
    end, { desc = '[G]rep in Open Files' })

    -- Shortcut for searching your Neovim configuration files
    vim.keymap.set('n', '<leader>sn', function()
      builtin.find_files { cwd = vim.fn.stdpath 'config' }
    end, { desc = '[n]eovim files' })

    -- Файловый браузер
    vim.keymap.set('n', '<leader>e', function()
      require('telescope').extensions.file_browser.file_browser({
        path = vim.fn.expand('%:p:h'),
        select_buffer = true,
      })
    end, { desc = 'File [e]xplorer' })
  end,
}
