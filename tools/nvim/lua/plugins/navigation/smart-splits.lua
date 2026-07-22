-- Ресайз сплитов: режим по <C-w>R — прямой аналог prefix+R в tmux (см. .tmux.conf).
-- Вошёл, жмёшь y/h/a/e сколько нужно, Escape выходит. Раскладка та же, что у
-- навигации (y/h/a/e = ←↓↑→), но двигает границу, а не фокус.
--
-- Зачем плагин, а не встроенный `vertical resize`: vanilla-команды меняют РАЗМЕР
-- ТЕКУЩЕГО ОКНА, а не двигают конкретную границу. У правого края `<C-w><` уезжает
-- левой границей — отсюда ощущение «жму не туда». resize_left двигает границу
-- влево независимо от того, где стоит окно, и одинаково работает в сетке, где
-- сплиты и вертикальные, и горизонтальные.
--
-- multiplexer_integration: упёрся в край nvim-сплита — та же клавиша начинает
-- двигать границу tmux-пейна. Плагин зовёт tmux напрямую через CLI, так что
-- никаких дополнительных биндов в .tmux.conf для этого не нужно.
--
-- Режим — свой цикл на getcharstr, а НЕ hydra-режим which-key. Причина: в
-- which-key стоит disable по buftype (terminal/quickfix/help/nofile/prompt), и
-- попап там не открывается вовсе — то есть режим отваливался бы ровно в тех
-- окнах, которые чаще всего и хочется растянуть. Проверено: в :help попап не
-- появлялся и клавиши не доходили.
--
-- Отличие от tmux, намеренное: там непривязанная клавиша съедается, здесь она
-- возвращается в буфер через feedkeys. Симметрию тут ломаем сознательно — в
-- редакторе потерянный символ дороже.
local DIRS = { y = 'left', h = 'down', a = 'up', e = 'right' }

local function resize_mode()
  local ss = require 'smart-splits'
  while true do
    vim.api.nvim_echo({ { 'RESIZE', 'WarningMsg' }, { '  y/h/a/e · Esc' } }, false, {})
    local ok, ch = pcall(vim.fn.getcharstr)
    vim.api.nvim_echo({ { '' } }, false, {})
    if not ok or ch == '\27' or ch == 'q' then
      return
    end
    local dir = DIRS[ch]
    if not dir then
      vim.api.nvim_feedkeys(ch, 'n', false)
      return
    end
    ss['resize_' .. dir]()
    vim.cmd.redraw()
  end
end

return {
  'mrjones2014/smart-splits.nvim',
  opts = { multiplexer_integration = 'tmux' },
  keys = {
    { '<C-w>R', resize_mode, desc = 'Resize mode' },
  },
}
