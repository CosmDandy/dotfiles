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
      config = function(_, opts)
        local path = '~/.local/share/nvim/mason/packages/debugpy/venv/bin/python'
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
      commented = true, -- Show virtual text alongside comment
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

    dapui.setup {}

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
