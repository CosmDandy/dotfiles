-- barbecue
-- https://github.com/utilyre/barbecue.nvim

return {
  'utilyre/barbecue.nvim',
  event = 'BufReadPost',
  name = 'barbecue',
  version = '*',
  dependencies = {
    'SmiteshP/nvim-navic',
  },
  opts = {},
}
