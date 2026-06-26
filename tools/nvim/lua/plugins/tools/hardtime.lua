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
    -- вертикаль стрелками — полностью запрещена (0 раз), вынуждает j/k + count, }/{, flash, поиск
    disabled_keys = {
      ['<Up>'] = { '', 'i' },
      ['<Down>'] = { '', 'i' },
      ['<Left>'] = {}, -- снимаем дефолтную полную блокировку — переводим в restricted ниже
      ['<Right>'] = {},
    },
    -- горизонталь стрелками — под общий max_count (5 раз), как hjkl
    restricted_keys = {
      ['<Left>'] = { 'n', 'x' },
      ['<Right>'] = { 'n', 'x' },
    },
  },
  -- stylua: ignore
  keys = {
    { '<leader>tH', '<cmd>Hardtime toggle<CR>', desc = 'Toggle [H]ardtime' },
  },
}
