-- venv-selector: выбор python-окружения из редактора, чтобы LSP и debugger
-- подхватывали тот же интерпретатор, что и терминал.
--
-- Ветка main (v1 больше не поддерживается). Требует fd — он в системе есть.
-- Пикер берётся из snacks: telescope в конфиге нет и возвращать его не нужно,
-- плагин умеет работать с snacks, fzf-lua, mini-pick и vim.ui.select.
--
-- Бинд в группе [c]ode: <leader>cv. Дефолтный ',v' не используем — запятая
-- в конфиге занята под собственные прыжки.
return {
  'linux-cultist/venv-selector.nvim',
  branch = 'main',
  ft = 'python',
  cmd = { 'VenvSelect', 'VenvSelectCache' },
  keys = {
    { '<leader>cv', '<cmd>VenvSelect<cr>', desc = '[v]env выбрать окружение' },
  },
  opts = {
    options = {},
    search = {},
  },
}
