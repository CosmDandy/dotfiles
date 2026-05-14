-- diffview.nvim — side-by-side diff и история файла/репозитория
-- https://github.com/sindrets/diffview.nvim
return {
  'sindrets/diffview.nvim',
  cmd = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewToggleFiles', 'DiffviewFocusFiles', 'DiffviewFileHistory' },
  keys = {
    { '<leader>gd', '<cmd>DiffviewOpen<cr>', desc = '[G]it [D]iff view' },
    { '<leader>gD', '<cmd>DiffviewClose<cr>', desc = '[G]it [D]iff close' },
    { '<leader>gh', '<cmd>DiffviewFileHistory %<cr>', desc = '[G]it file [H]istory' },
    { '<leader>gH', '<cmd>DiffviewFileHistory<cr>', desc = '[G]it repo [H]istory' },
  },
  opts = {
    enhanced_diff_hl = true,
    view = {
      merge_tool = {
        layout = 'diff3_mixed',
        disable_diagnostics = true,
      },
    },
  },
}
