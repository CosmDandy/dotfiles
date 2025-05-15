-- debug.lua
--
-- Shows how to use the DAP plugin to debug your code.
--
-- Primarily focused on configuring the debugger for Go, but can
-- be extended to other languages as well. That's why it's called
-- kickstart.nvim and not kitchen-sink.nvim ;)

return {
  'mfussenegger/nvim-dap',
  dependencies = {
    'rcarriga/nvim-dap-ui',
    'nvim-neotest/nvim-nio',
    'williamboman/mason.nvim',
    'jay-babu/mason-nvim-dap.nvim',
    'theHamsta/nvim-dap-virtual-text',
    { 'nvim-telescope/telescope-dap.nvim' },
    {
      'mfussenegger/nvim-dap-python',
      ft = 'python',
      config = function()
        -- ИЗМЕНЕНО: Улучшенная автоматическая настройка debugpy
        local path = vim.fn.stdpath("data") .. '/mason/packages/debugpy/venv/bin/python'
        require('dap-python').setup(path)

        -- НОВОЕ: Добавление testpy для тестирования
        require('dap-python').test_runner = 'pytest'

        -- НОВОЕ: Настройка представлений переменных для лучшей читаемости
        require('dap-python').resolve_python = function()
          return path
        end
      end,
    },
    -- НОВОЕ: Продвинутая визуализация профилирования для Python
    { 'lvimuser/lsp-inlayhints.nvim' }, -- для отображения подсказок типов

    -- НОВОЕ: Улучшенное отображение ошибок и состояний отладки
    {
      'folke/trouble.nvim',
      dependencies = { 'nvim-tree/nvim-web-devicons' },
    },
  },
  keys = {
    {
      '<F5>',
      function()
        require('dap').continue()
      end,
      desc = 'Start/Continue',
    },
    {
      '<F1>',
      function()
        require('dap').step_into()
      end,
      desc = 'Step Into',
    },
    {
      '<F2>',
      function()
        require('dap').step_over()
      end,
      desc = 'Step Over',
    },
    {
      '<F3>',
      function()
        require('dap').step_out()
      end,
      desc = 'Step Out',
    },
    {
      '<leader>b',
      function()
        require('dap').toggle_breakpoint()
      end,
      desc = '[b]reakpoint toggle',
    },
    {
      '<leader>B',
      function()
        require('dap').set_breakpoint(vim.fn.input 'Breakpoint condition: ')
      end,
      desc = '[B]reakpoint set',
    },
    {
      '<F7>',
      function()
        require('dapui').toggle()
      end,
      desc = 'See last session result.',
    },
    -- НОВОЕ: Дополнительные полезные сочетания клавиш
    {
      '<leader>dc',
      function()
        require('telescope').extensions.dap.commands()
      end,
      desc = '[d]ebug [c]ommands',
    },
    {
      '<leader>dv',
      function()
        require('telescope').extensions.dap.variables()
      end,
      desc = '[d]ebug [v]ariables',
    },
    {
      '<leader>df',
      function()
        require('telescope').extensions.dap.frames()
      end,
      desc = '[d]ebug [f]rames',
    },
    {
      '<leader>dt',
      function()
        require('dap-python').test_method()
      end,
      desc = '[d]ebug [t]est method',
    },
    {
      '<leader>dT',
      function()
        require('dap-python').test_class()
      end,
      desc = '[d]ebug [T]est class',
    },
    {
      '<leader>dpp',
      function()
        -- НОВОЕ: Запуск профилирования текущего файла
        local Terminal = require('toggleterm.terminal').Terminal
        local prof_term = Terminal:new({
          cmd = string.format(
            "python -m cProfile -o profile.prof %s && python -m pyprof2calltree -i profile.prof -o profile.calltree && kcachegrind profile.calltree",
            vim.fn.expand("%:p")),
          hidden = false,
        })
        prof_term:toggle()
      end,
      desc = '[d]ebug [p]rofile [p]ython',
    },
    {
      '<leader>dpm',
      function()
        -- НОВОЕ: Запуск memory_profiler для текущего файла
        local Terminal = require('toggleterm.terminal').Terminal
        local memprof_term = Terminal:new({
          cmd = string.format("python -m memory_profiler %s", vim.fn.expand("%:p")),
          hidden = false,
        })
        memprof_term:toggle()
      end,
      desc = '[d]ebug [p]rofile [m]emory',
    },
    {
      '<leader>dps',
      function()
        -- НОВОЕ: Запуск scalene профилировщика
        local Terminal = require('toggleterm.terminal').Terminal
        local scalene_term = Terminal:new({
          cmd = string.format("python -m scalene %s", vim.fn.expand("%:p")),
          hidden = false,
        })
        scalene_term:toggle()
      end,
      desc = '[d]ebug [p]rofile [s]calene',
    },
  },
  config = function()
    local dap = require 'dap'
    local dapui = require 'dapui'

    require('mason-nvim-dap').setup {
      automatic_installation = true,
      -- You can provide additional configuration to the handlers,
      -- see mason-nvim-dap README for more information
      handlers = {},

      -- You'll need to check that you have the required things installed
      -- online, please don't ask me how to install them :)
      ensure_installed = {
        -- Update this to ensure that you have the debuggers for the langs you want
        'delve',
        'pyright',
      },
    }

    require('nvim-dap-virtual-text').setup {
      enabled = true,                     -- включено по умолчанию
      enabled_commands = true,            -- команды для включения/отключения
      highlight_changed_variables = true, -- подсветка измененных переменных
      highlight_new_as_changed = true,    -- подсветка новых переменных
      show_stop_reason = true,            -- показ причины остановки
      commented = true,                   -- текст как комментарии
      only_first_definition = false,      -- показать только первое определение
      all_references = true,              -- показать все ссылки
      all_frames = false,                 -- показать значения из всех фреймов
      virt_text_pos = 'eol',              -- позиция виртуального текста
      virt_text_win_col = nil,            -- фиксированная позиция столбца
    }

    require('telescope').load_extension('dap')

    require('trouble').setup {
      position = "bottom",
      height = 10,
      auto_preview = false,
      auto_close = true,
    }

    -- Настройка интерфейса отладчика
    -- dapui.setup({
    --   layouts = {
    --     {
    --       elements = {
    --         { id = "scopes",      size = 0.25 },
    --         { id = "breakpoints", size = 0.25 },
    --         { id = "stacks",      size = 0.25 },
    --         { id = "watches",     size = 0.25 },
    --       },
    --       size = 40,
    --       position = "left",
    --     },
    --     {
    --       elements = {
    --         { id = "repl",    size = 0.5 },
    --         { id = "console", size = 0.5 },
    --       },
    --       size = 10,
    --       position = "bottom",
    --     },
    --   },
    -- })
    -- ИЗМЕНЕНО: Улучшенная настройка дизайна dapui
    dapui.setup {
      controls = {
        element = "repl",
        enabled = true,
        icons = {
          disconnect = "",
          pause = "",
          play = "",
          run_last = "",
          step_back = "",
          step_into = "",
          step_out = "",
          step_over = "",
          terminate = ""
        }
      },
      element_mappings = {},
      expand_lines = true,
      floating = {
        border = "single",
        mappings = {
          close = { "q", "<Esc>" }
        }
      },
      force_buffers = true,
      icons = {
        collapsed = "",
        current_frame = "",
        expanded = ""
      },
      layouts = {
        {
          elements = {
            {
              id = "scopes",
              size = 0.4
            },
            {
              id = "breakpoints",
              size = 0.15
            },
            {
              id = "stacks",
              size = 0.25
            },
            {
              id = "watches",
              size = 0.2
            }
          },
          position = "left",
          size = 40
        },
        {
          elements = {
            {
              id = "repl",
              size = 0.5
            },
            {
              id = "console",
              size = 0.5
            }
          },
          position = "bottom",
          size = 15
        }
      },
      mappings = {
        edit = "e",
        expand = { "<CR>", "<2-LeftMouse>" },
        open = "o",
        remove = "d",
        repl = "r",
        toggle = "t"
      },
      render = {
        indent = 1,
        max_value_lines = 100
      }
    }


    dap.adapters.python = {
      type = 'server',
      host = 'localhost',
      port = 5678,
    }

    dap.configurations.python = {
      {
        type = 'python',
        request = 'launch',
        name = 'Local Python',
        program = '${file}',
        pythonPath = function()
          return vim.fn.expand '.venv/bin/python' -- Измените путь на путь к вашему виртуальному окружению
        end,
      },
      {
        name = 'Odoo Local',
        type = 'python',
        request = 'attach',
        connect = {
          host = 'localhost',
          port = 5678,
        },
        justMyCode = false,
        pathMappings = {
          {
            localRoot = '${workspaceFolder}/addons/main',
            remoteRoot = '/mnt/extra-addons/main',
          },
          {
            localRoot = '${workspaceFolder}/addons/third-party',
            remoteRoot = '/mnt/extra-addons/third-party',
          },
          {
            localRoot = '${workspaceFolder}/addons/icode',
            remoteRoot = '/mnt/extra-addons/icode',
          },
          {
            localRoot = '${workspaceFolder}/addons/oca',
            remoteRoot = '/mnt/extra-addons/oca',
          },
          {
            localRoot = '${workspaceFolder}/odoo/addons',
            remoteRoot = '/usr/lib/python3/dist-packages/odoo/addons',
          },
          {
            localRoot = '${workspaceFolder}/odoo/api.py',
            remoteRoot = '/usr/lib/python3/dist-packages/odoo/api.py',
          },
          {
            localRoot = '${workspaceFolder}/addons/src_volumes/models.py',
            remoteRoot = '/usr/lib/python3/dist-packages/odoo/models.py',
          },
          {
            localRoot = '${workspaceFolder}/odoo/service',
            remoteRoot = '/usr/lib/python3/dist-packages/odoo/service',
          },
          {
            localRoot = '${workspaceFolder}/addons/src_volumes/fields.py',
            remoteRoot = '/usr/lib/python3/dist-packages/odoo/fields.py',
          },
          {
            localRoot = '${workspaceFolder}/odoo',
            remoteRoot = '/usr/lib/python3/dist-packages/odoo',
          },
        },
      },
      {
        name = 'Stage Server',
        type = 'python',
        request = 'attach',
        connect = {
          host = '192.168.82.50',
          port = 7013,
        },
        justMyCode = false,
        pathMappings = {
          {
            localRoot = '${workspaceFolder}/addons/main',
            remoteRoot = '/mnt/extra-addons/main',
          },
          {
            localRoot = '${workspaceFolder}/addons/third-party',
            remoteRoot = '/mnt/extra-addons/third-party',
          },
          {
            localRoot = '${workspaceFolder}/addons/icode',
            remoteRoot = '/mnt/extra-addons/icode',
          },
          {
            localRoot = '${workspaceFolder}/src/odoo-13.0.post20200131/odoo/addons',
            remoteRoot = '/usr/lib/python3/dist-packages/odoo/addons',
          },
          {
            localRoot = '${workspaceFolder}/src/odoo-13.0.post20200131/odoo/addons/base/models/ir_model.py',
            remoteRoot = '/usr/lib/python3/dist-packages/odoo/addons/base/models/ir_model.py',
          },
          {
            localRoot = '${workspaceFolder}/addons/src_volumes/fields.py',
            remoteRoot = '/usr/lib/python3/dist-packages/odoo/fields.py',
          },
        },
      },
      {
        name = 'Develop Server',
        type = 'python',
        request = 'attach',
        connect = {
          host = '192.168.82.50',
          port = 9013,
        },
        justMyCode = false,
        pathMappings = {
          {
            localRoot = '${workspaceFolder}/addons/main',
            remoteRoot = '/mnt/extra-addons/main',
          },
          {
            localRoot = '${workspaceFolder}/addons/third-party',
            remoteRoot = '/mnt/extra-addons/third-party',
          },
          {
            localRoot = '${workspaceFolder}/addons/icode',
            remoteRoot = '/mnt/extra-addons/icode',
          },
          {
            localRoot = '${workspaceFolder}/src/odoo-13.0.post20200131/odoo/addons',
            remoteRoot = '/usr/lib/python3/dist-packages/odoo/addons',
          },
          {
            localRoot = '${workspaceFolder}/src/odoo-13.0.post20200131/odoo/addons/base/models/ir_model.py',
            remoteRoot = '/usr/lib/python3/dist-packages/odoo/addons/base/models/ir_model.py',
          },
          {
            localRoot = '${workspaceFolder}/addons/src_volumes/fields.py',
            remoteRoot = '/usr/lib/python3/dist-packages/odoo/fields.py',
          },
        },
      },
    }
    vim.api.nvim_set_hl(0, 'DapBreak', { fg = '#e51400' })
    vim.api.nvim_set_hl(0, 'DapStop', { fg = '#ffcc00' })
    vim.api.nvim_set_hl(0, 'DapContinue', { fg = '#00ff00' })
    vim.api.nvim_set_hl(0, 'DapLogPoint', { fg = '#00bfff' })

    -- НОВОЕ: Интеграция с inlayhints для отображения типов при отладке
    require('lsp-inlayhints').setup {
      inlay_hints = {
        parameter_hints = {
          show = true,
          prefix = "<- ",
          separator = ", ",
          remove_colon_start = false,
          remove_colon_end = false,
        },
        type_hints = {
          show = true,
          prefix = "=> ",
          separator = ", ",
          remove_colon_start = false,
          remove_colon_end = false,
        },
        only_current_line = false,
        highlight = "Comment",
      }
    }

    -- Change breakpoint icons
    -- vim.api.nvim_set_hl(0, 'DapBreak', { fg = '#e51400' })
    -- vim.api.nvim_set_hl(0, 'DapStop', { fg = '#ffcc00' })
    -- local breakpoint_icons = vim.g.have_nerd_font
    --     and { Breakpoint = '', BreakpointCondition = '', BreakpointRejected = '', LogPoint = '', Stopped = '' }
    --   or { Breakpoint = '●', BreakpointCondition = '⊜', BreakpointRejected = '⊘', LogPoint = '◆', Stopped = '⭔' }
    -- for type, icon in pairs(breakpoint_icons) do
    --   local tp = 'Dap' .. type
    --   local hl = (type == 'Stopped') and 'DapStop' or 'DapBreak'
    --   vim.fn.sign_define(tp, { text = icon, texthl = hl, numhl = hl })
    -- end

    dap.listeners.after.event_initialized['dapui_config'] = dapui.open
    dap.listeners.before.event_terminated['dapui_config'] = dapui.close
    dap.listeners.before.event_exited['dapui_config'] = dapui.close
  end,
}
