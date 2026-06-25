-- diffview.nvim — side-by-side diff и история файла/репозитория
-- форк diffview-plus: оригинал sindrets заброшен с 06.2024; drop-in (модуль 'diffview' тот же)
-- https://github.com/dlyongemallo/diffview-plus.nvim
return {
  'dlyongemallo/diffview-plus.nvim',
  cmd = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewToggleFiles', 'DiffviewFocusFiles', 'DiffviewFileHistory' },
  keys = {
    { '<leader>gdv', '<cmd>DiffviewOpen<cr>', desc = '[v]iew diff' },
    { '<leader>gdq', '<cmd>DiffviewClose<cr>', desc = '[q]uit diff view' },
    { '<leader>gdh', '<cmd>DiffviewFileHistory %<cr>', desc = 'file [h]istory' },
    { '<leader>gdH', '<cmd>DiffviewFileHistory<cr>', desc = 'repo [H]istory' },
  },
  opts = {
    enhanced_diff_hl = true,
    file_panel = {
      win_config = { width = 45 }, -- шире — не обрезает глубокие пути k8s/helm
    },
    hooks = {
      -- в diff-буферах без wrap/list — меньше визуального шума на широких TF/Helm
      diff_buf_read = function()
        vim.opt_local.wrap = false
        vim.opt_local.list = false
      end,
    },
    view = {
      merge_tool = {
        layout = 'diff3_mixed',
        disable_diagnostics = true,
      },
    },
  },
}
