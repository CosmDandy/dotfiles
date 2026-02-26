return {
  'MagicDuck/grug-far.nvim',
  keys = {
    {
      '<leader>ss',
      function()
        require('grug-far').open { transient = true }
      end,
      mode = { 'n', 'x' },
      desc = '[S]earch & Replace',
    },
  },
  opts = {},
}
