-- Breaks the bad habits: spamming hjkl or arrows and repeating the same command.
return {
  'm4xshen/hardtime.nvim',
  dependencies = { 'MunifTanjim/nui.nvim' },
  event = 'BufReadPost',
  opts = {
    -- full hard mode: inefficient motions are blocked outright
    restriction_mode = 'block', -- не выполнять «плохую» команду вовсе (а не просто подсказывать)
    max_count = 5, -- лимит повторов подряд (общий для restricted_keys: hjkl + горизонтальные стрелки)
    max_time = 1000, -- окно (мс), в котором считаются повторы
    hint = true, -- показывать подсказку о более эффективной команде
    notification = true,
    disable_mouse = true, -- мышь в редакторе тоже отучаем
    -- lift the default total block on the arrows; they become restricted below
    disabled_keys = {
      ['<Up>'] = {},
      ['<Down>'] = {},
      ['<Left>'] = {},
      ['<Right>'] = {},
    },
    -- arrows are treated exactly like hjkl: the same max_count in normal and visual
    restricted_keys = {
      ['<Up>'] = { 'n', 'x' },
      ['<Down>'] = { 'n', 'x' },
      ['<Left>'] = { 'n', 'x' },
      ['<Right>'] = { 'n', 'x' },
    },
  },
  -- stylua: ignore
  keys = {
    { '<leader>tH', '<cmd>Hardtime toggle<CR>', desc = 'Toggle [H]ardtime' },
  },
}
