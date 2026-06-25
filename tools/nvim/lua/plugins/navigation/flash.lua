return {
  'folke/flash.nvim',
  event = 'BufReadPre',
  ---@type Flash.Config
  opts = {
    search = { multi_window = true },
    -- remote (r в operator-pending): после операции вернуть курсор/вью на место
    remote_op = { restore = true },
    label = {
      current = true, -- подсвечивать и совпадение под курсором
      rainbow = { enabled = true, shade = 5 }, -- цветные лейблы по дистанции — читаются легче
    },
    modes = {
      -- обычный / поиск не трогаем (никаких лейблов), flash в нём включается по <c-s>
      search = { enabled = false },
      char = {
        -- f/t/F/T получают jump-labels: после мотиона прыжок на любое совпадение
        jump_labels = true,
        label = { exclude = 'hjkliardc' }, -- не занимать лейблами ходовые motion-клавиши
        -- не показывать лейблы при счётчике (3f) и во время записи/проигрывания макроса
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
