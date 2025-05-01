return {
  'epwalsh/obsidian.nvim',
  enabled = false,
  version = '*',
  lazy = true,
  ft = 'markdown',
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  completion = {
    nvim_cmp = true,
    min_chars = 2,
  },
  opts = {
    workspaces = {
      {
        name = 'KnowledgeBase',
        path = '~/KnowledgeBase/',
      },
    },
  },
}
