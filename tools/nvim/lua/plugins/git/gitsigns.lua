return {
  'lewis6991/gitsigns.nvim',
  event = 'BufRead',
  opts = {
    -- unstaged changes use a thin bar, staged a thick one
    signs = {
      add = { text = '│' },
      change = { text = '│' },
      delete = { text = '_' },
      topdelete = { text = '‾' },
      changedelete = { text = '~' },
    },
    -- separate signs for staged hunks, so the index is visible at a glance
    signs_staged = {
      add = { text = '┃' },
      change = { text = '┃' },
      delete = { text = '_' },
      topdelete = { text = '‾' },
    },
    -- word-level highlighting inside the buffer
    word_diff = true,
    -- signs on untracked files too, so they can be staged hunk by hunk without git add
    attach_to_untracked = true,
    -- current-line blame at the end of the line; <leader>gt toggles it
    current_line_blame = true,
    current_line_blame_opts = {
      delay = 2500,
    },
    max_file_length = 200000,
    preview_config = {
      border = 'rounded',
      style = 'minimal',
      relative = 'cursor',
      row = 0,
      col = 1,
    },
    on_attach = function(bufnr)
      local gitsigns = require 'gitsigns'

      local function map(mode, l, r, opts)
        opts = opts or {}
        opts.buffer = bufnr
        vim.keymap.set(mode, l, r, opts)
      end

      -- Navigation
      map('n', ']c', function()
        if vim.wo.diff then
          vim.cmd.normal { ']c', bang = true }
        else
          gitsigns.nav_hunk 'next'
        end
      end, { desc = 'Next git [c]hange' })

      map('n', '[c', function()
        if vim.wo.diff then
          vim.cmd.normal { '[c', bang = true }
        else
          gitsigns.nav_hunk 'prev'
        end
      end, { desc = 'Previous git [c]hange' })

      -- Actions
      -- visual mode
      map('v', '<leader>gs', function()
        gitsigns.stage_hunk { vim.fn.line '.', vim.fn.line 'v' }
      end, { desc = '[s]tage hunk' })
      map('v', '<leader>gr', function()
        gitsigns.reset_hunk { vim.fn.line '.', vim.fn.line 'v' }
      end, { desc = '[r]eset hunk' })

      -- normal mode
      map('n', '<leader>gs', gitsigns.stage_hunk, { desc = '[s]tage hunk' })
      map('n', '<leader>gr', gitsigns.reset_hunk, { desc = '[r]eset hunk' })
      map('n', '<leader>gS', gitsigns.stage_buffer, { desc = '[S]tage buffer' })
      map('n', '<leader>gR', gitsigns.reset_buffer, { desc = '[R]eset buffer' })
      map('n', '<leader>gP', gitsigns.preview_hunk, { desc = '[P]review hunk' })
      map('n', '<leader>gp', gitsigns.preview_hunk_inline, { desc = '[p]review hunk inline' })
      map('n', '<leader>gB', gitsigns.blame, { desc = '[B]lame' })
      map('n', '<leader>gt', gitsigns.toggle_current_line_blame, { desc = '[t]oggle current-line blame' })
      map('n', '<leader>gdi', gitsigns.diffthis, { desc = '[d]iff against [i]ndex' })
      map('n', '<leader>gdc', function()
        gitsigns.diffthis '@'
      end, { desc = '[d]iff against last [c]ommit' })
    end,
  },
}
