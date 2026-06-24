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
      '<F3>',
      function()
        require('dap').step_into()
      end,
      desc = 'Step Into',
    },
    {
      '<F6>',
      function()
        require('dap').step_over()
      end,
      desc = 'Step Over',
    },
    {
      '<F9>',
      function()
        require('dap').step_out()
      end,
      desc = 'Step Out',
    },
    {
      '<F8>',
      function()
        require('dap').terminate()
      end,
      desc = 'Terminate',
    },
    {
      '<F4>',
      function()
        require('dap').restart()
      end,
      desc = 'Restart',
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
        require('dapui').toggle()
      end,
      desc = '[d]ebug [c]ommands',
    },
    {
      '<leader>dv',
      function()
        require('dapui').float_element('scopes')
      end,
      desc = '[d]ebug [v]ariables',
    },
    {
      '<leader>df',
      function()
        require('dapui').float_element('stacks')
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
        'debugpy',
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

    dapui.setup {
      controls = {
        element = "repl",
        enabled = true,
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


    dap.configurations.python = {
      {
        type = 'python',
        request = 'launch',
        name = 'Local Python',
        program = '${file}',
        pythonPath = function()
          return vim.fn.expand '.venv/bin/python'
        end,
      },
    }

    -- Change breakpoint icons
    vim.api.nvim_set_hl(0, 'DapBreak', { fg = '#e51400' })
    vim.api.nvim_set_hl(0, 'DapStop', { fg = '#ffcc00' })
    vim.api.nvim_set_hl(0, 'DapContinue', { fg = '#00ff00' })
    vim.api.nvim_set_hl(0, 'DapLogPoint', { fg = '#00bfff' })
    local breakpoint_icons = vim.g.have_nerd_font
        and { Breakpoint = '', BreakpointCondition = '', BreakpointRejected = '', LogPoint = '', Stopped = '' }
        or { Breakpoint = '●', BreakpointCondition = '⊜', BreakpointRejected = '⊘', LogPoint = '◆', Stopped = '⭔' }
    for type, icon in pairs(breakpoint_icons) do
      local tp = 'Dap' .. type
      local hl = (type == 'Stopped') and 'DapStop' or 'DapBreak'
      vim.fn.sign_define(tp, { text = icon, texthl = hl, numhl = hl })
    end

    dap.listeners.after.event_initialized['dapui_config'] = dapui.open
    dap.listeners.before.event_terminated['dapui_config'] = dapui.close
    dap.listeners.before.event_exited['dapui_config'] = dapui.close
  end,
}
