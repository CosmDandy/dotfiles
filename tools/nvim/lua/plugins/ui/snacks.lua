-- snacks.nvim — folke's modular utility set: https://github.com/folke/snacks.nvim

-- A vertical window with a configurable preview share at the bottom (0.6 = 60% preview).
-- NOTE: returns a fresh table on every call, so the sources below share no references.
local function vertical(preview_ratio)
  return {
    layout = {
      layout = {
        box = 'vertical',
        width = 0.9,
        height = 0.9,
        border = true,
        title = '{title} {live} {flags}',
        title_pos = 'center',
        { win = 'input', height = 1, border = 'bottom' },
        { win = 'list', border = 'none' },
        { win = 'preview', title = '{preview}', height = preview_ratio, border = 'top' },
      },
    },
  }
end

-- Centred window with no preview — the 'select' preset hides it.
local function select()
  return { layout = { preset = 'select', layout = { width = 0.6, height = 0.5 } } }
end

local exclude = {
  '.git',
  'node_modules',
  '__pycache__',
  '*.pyc',
  '.venv',
  'venv',
  '*.min.js',
  '*.min.css',
  'var',
  '*.egg-info',
}
local function with_exclude(cfg)
  cfg.exclude = exclude
  return cfg
end

return {
  'folke/snacks.nvim',
  priority = 1000,
  lazy = false,
  ---@type snacks.Config
  opts = {
    bigfile = {
      enabled = true,
      notify = true,
      size = 1.5 * 1024 * 1024,
    },
    -- NOTE: inline image rendering is off — it is not needed and breaks treesitter on
    -- nvim 0.12 (the range method).
    image = { enabled = false },
    -- draw the file immediately when opened from the shell, before plugins load
    quickfile = { enabled = true },
    -- floating vim.ui.input instead of the bottom line
    input = { enabled = true },
    -- Smooth scroll: an instant half-screen jump makes you re-find where you are, while
    -- the animation leads the eye.
    -- NOTE: the default filter leaves buftype=terminal alone (lazygit, claude-code),
    -- where the application draws its own scrolling.
    scroll = { enabled = true },
    -- LSP document_highlight for the symbol under the cursor, plus ]]/[[ jumps
    words = { enabled = true },
    -- scope textobjects: ii/ai and the [i/]i jumps
    scope = { enabled = true },
    -- replaced nvim-notify; 'compact' keeps the border with an icon and title
    notifier = {
      enabled = true,
      timeout = 3000,
      style = 'compact',
      top_down = true,
    },
    styles = {
      notification = {
        border = 'rounded',
        wo = { winblend = 0 },
      },
      notification_history = {
        border = 'rounded',
        wo = { winblend = 0 },
      },
    },
    dashboard = {
      enabled = true,
      preset = {
        header = ' GO BIG OR GO HOME',
      },
      sections = {
        { section = 'header' },
        function()
          local stats = require('lazy').stats()
          return {
            align = 'center',
            padding = 1,
            text = { { ('◎ %dms'):format(math.floor(stats.startuptime + 0.5)), hl = 'SnacksDashboardFooter' } },
          }
        end,
      },
    },
    picker = {
      enabled = true,
      ui_select = true, -- replaces vim.ui.select
      -- frecency floats frequently and recently opened files to the top
      matcher = { frecency = true },
      -- filename first, directory after — shorter and easier to scan
      formatters = {
        file = {
          filename_first = true,
          truncate = 80,
        },
      },
      sources = {
        files = with_exclude(vertical(0.6)),
        grep = with_exclude(vertical(0.6)),
        grep_buffers = with_exclude(vertical(0.6)),
        grep_word = with_exclude(vertical(0.6)),
        diagnostics = vertical(0.6),
        git_log = vertical(0.6),
        git_log_file = vertical(0.8),
        git_branches = vertical(0.6),
        -- marks keep a preview so the mark's context is visible
        marks = { layout = { preset = 'dropdown' } },
        buffers = select(),
        recent = select(),
        pickers = select(),
        keymaps = select(),
        search_history = select(),
        -- buffer lines: preview at the bottom, so long lines are visible in full
        lines = vertical(0.6),
        -- :help — preview on the right, the article is readable before jumping
        help = { layout = { preset = 'default' } },
        -- NOTE: filter=true for the config filetypes — LSP marks their structure as
        -- Object/Key/Variable, and the snacks default filter hides exactly those types,
        -- which is why the document-symbol picker came up empty there.
        lsp_symbols = {
          layout = { preset = 'default' },
          filter = {
            yaml = true,
            json = true,
            terraform = true,
            helm = true,
            dockerfile = true,
          },
        },
        -- workspace symbols go vertical so the file paths are visible
        lsp_workspace_symbols = vertical(0.5),
        lsp_incoming_calls = { layout = { preset = 'default' } },
        lsp_outgoing_calls = { layout = { preset = 'default' } },
        -- treesitter symbols: needed where LSP gives none — hcl, gotmpl, csv
        treesitter = { layout = { preset = 'default' } },
        -- registers: the content is visible in the row itself, so the default preview
        -- window is disproportionately large
        registers = { layout = { preset = 'dropdown' } },
        -- for git status/diff the diff preview matters more than the file list
        git_status = vertical(0.6),
        git_diff = vertical(0.7),
      },
    },
    indent = {
      enabled = true,
      indent = {
        char = '┊',
        hl = 'SnacksIndent',
      },
      scope = {
        enabled = true,
        char = '│',
        underline = false,
        hl = {
          'SnacksIndent1',
          'SnacksIndent2',
          'SnacksIndent3',
          'SnacksIndent4',
          'SnacksIndent5',
          'SnacksIndent6',
        },
      },
      chunk = { enabled = false },
      animate = { enabled = false },
      filter = function(buf)
        local ft = vim.bo[buf].filetype
        local excluded = {
          help = true,
          dashboard = true,
          lazy = true,
          mason = true,
          oil = true,
        }
        return vim.g.snacks_indent ~= false and vim.b[buf].snacks_indent ~= false and not excluded[ft]
      end,
    },
  },
}
