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
    'mason-org/mason.nvim',
    'theHamsta/nvim-dap-virtual-text',
    {
      'mfussenegger/nvim-dap-python',
      ft = 'python',
      config = function()
        -- debugpy-адаптер из mason-venv; python для отлаживаемой программы
        -- dap-python определяет сам (.venv проекта / VIRTUAL_ENV)
        local path = vim.fn.stdpath 'data' .. '/mason/packages/debugpy/venv/bin/python'
        require('dap-python').setup(path)
        require('dap-python').test_runner = 'pytest'
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
    {
      '<leader>dc',
      function()
        require('dap').continue()
      end,
      desc = '[d]ebug [c]ontinue',
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
    {
      '<leader>dC',
      function()
        require('dap').run_to_cursor()
      end,
      desc = '[d]ebug run to [C]ursor',
    },
    {
      '<leader>dl',
      function()
        require('dap').run_last()
      end,
      desc = '[d]ebug run [l]ast',
    },
    {
      '<leader>de',
      function()
        require('dapui').eval()
      end,
      mode = { 'n', 'v' },
      desc = '[d]ebug [e]val expression',
    },
    {
      '<leader>dx',
      function()
        require('dap').set_exception_breakpoints { 'raised', 'uncaught' }
      end,
      desc = '[d]ebug e[x]ception breakpoints',
    },
    {
      '<leader>dL',
      function()
        require('dap').set_breakpoint(nil, nil, vim.fn.input 'Log point message: ')
      end,
      desc = '[d]ebug [L]og point',
    },
  },
  config = function()
    local dap = require 'dap'
    local dapui = require 'dapui'

    -- debugpy ставит mason-tool-installer (lsp.lua), отдельный mason-nvim-dap не нужен

    require('nvim-dap-virtual-text').setup {
      -- только отличия от дефолта upstream:
      highlight_new_as_changed = true, -- новые переменные подсвечивать как изменённые
      commented = true,                -- виртуальный текст в виде комментария
      only_first_definition = false,   -- показывать у всех вхождений, не только первого
      all_references = true,           -- показывать все ссылки
      virt_text_pos = 'eol',           -- на 0.10+ дефолт 'inline', нам нужен eol
    }

    dapui.setup {
      -- icons: пустые строки = без глифов сворачивания (НЕ дефолт; дефолт — глифы-треугольники)
      icons = {
        collapsed = "",
        current_frame = "",
        expanded = "",
      },
      -- кастомные доли панелей (дефолт — равные 0.25)
      layouts = {
        {
          elements = {
            { id = "scopes", size = 0.4 },
            { id = "breakpoints", size = 0.15 },
            { id = "stacks", size = 0.25 },
            { id = "watches", size = 0.2 },
          },
          position = "left",
          size = 40,
        },
        {
          elements = {
            { id = "repl", size = 0.5 },
            { id = "console", size = 0.5 },
          },
          position = "bottom",
          size = 15,
        },
      },
      render = { max_value_lines = 100 }, -- остальное (controls/floating/mappings/expand_lines) = дефолт
    }


    -- .vscode/launch.json читается автоматически on-demand (:help dap-providers) —
    -- ручной load_launchjs больше не нужен (deprecated).
    -- Ручной dap.configurations.python убран: его 'Local Python' конфликтовал с конфигами,
    -- которые регистрирует require('dap-python').setup(path).

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
