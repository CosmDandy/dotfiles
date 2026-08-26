return {
  'folke/flash.nvim',
  -- no event needed: the keys spec below loads the plugin on s/S/r/R/<c-s>
  ---@type Flash.Config
  opts = {
    search = { multi_window = true },
    -- remote (r in operator-pending): restore the cursor and view after the operation
    remote_op = { restore = true },
    label = {
      current = true, -- подсвечивать и совпадение под курсором
      rainbow = { enabled = true, shade = 5 }, -- цветные лейблы по дистанции — читаются легче
    },
    modes = {
      -- plain / search is left alone; flash joins it on <c-s>
      search = { enabled = false },
      char = {
        -- f/t/F/T get jump labels, so the motion can reach any match
        jump_labels = true,
        label = { exclude = 'yhaeirdc' }, -- не занимать лейблами nav-клавиши Graphite (y/h/a/e) и операторы i/r/d/c
        -- NOTE: no labels with a count (3f) or while recording/replaying a macro
        config = function(opts)
          opts.jump_labels = opts.jump_labels and vim.v.count == 0 and vim.fn.reg_executing() == '' and vim.fn.reg_recording() == ''
        end,
      },
    },
  },
  -- stylua: ignore
  keys = {
    { "s",     mode = { "n", "x", "o" }, function() require("flash").jump() end,              desc = "Flash" },
    { "S",     mode = { "n", "x", "o" }, function() require("flash").treesitter() end,        desc = "Flash Treesitter" },
    { "r",     mode = "o",               function() require("flash").remote() end,            desc = "Remote Flash" },
    { "R",     mode = { "o", "x" },      function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
    { "<c-s>", mode = { "c" },           function() require("flash").toggle() end,            desc = "Toggle Flash Search" },
  },
}
