-- отучает от плохих привычек: спама hjkl/стрелок, повторов одних и тех же команд [https://github.com/m4xshen/hardtime.nvim]
return {
  'm4xshen/hardtime.nvim',
  dependencies = { 'MunifTanjim/nui.nvim' },
  event = 'BufReadPost',
  opts = {
    -- полный hard mode: жёстко блокируем неэффективные движения
    restriction_mode = 'block', -- не выполнять «плохую» команду вовсе (а не просто подсказывать)
    max_count = 5, -- лимит повторов подряд (общий для restricted_keys: hjkl + горизонтальные стрелки)
    max_time = 1000, -- окно (мс), в котором считаются повторы
    hint = true, -- показывать подсказку о более эффективной команде
    notification = true,
    disable_mouse = true, -- мышь в редакторе тоже отучаем
    -- снимаем дефолтную полную блокировку всех стрелок — переводим их в restricted ниже
    disabled_keys = {
      ['<Up>'] = {},
      ['<Down>'] = {},
      ['<Left>'] = {},
      ['<Right>'] = {},
    },
    -- стрелки полностью приравнены к hjkl: тот же max_count (5 раз) в режимах n + visual
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
