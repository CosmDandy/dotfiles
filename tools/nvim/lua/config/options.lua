-- Options
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '
vim.g.have_nerd_font = true -- Set to true if you have a Nerd Font installed and selected in the terminal
vim.opt.number = true -- Make line numbers default
vim.opt.relativenumber = true
vim.opt.mouse = '' -- мышь отключена (клавиатура-only); hardtime тоже её держит
vim.opt.showmode = false -- Don't show the mode, since it's already in the status line

vim.schedule(function() -- Sync clipboard between OS and Neovim.
  vim.opt.clipboard = 'unnamedplus'
end)

vim.opt.numberwidth = 5
vim.opt.fillchars:append { eob = ' ' } -- Убираем символы тильды (~) в пустых строках
vim.opt.breakindent = true -- Enable break indent
vim.opt.breakindentopt = 'shift:2' -- отступ перенесённых длинных строк (YAML/HCL)
vim.opt.undofile = true -- Save undo history
vim.opt.ignorecase = true
vim.opt.smartcase = true -- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.opt.signcolumn = 'yes' -- Keep signcolumn on by default
vim.opt.updatetime = 250 -- Decrease update time
vim.opt.timeoutlen = 300 -- Decrease mapped sequence wait time
vim.opt.splitright = true
vim.opt.splitbelow = true -- Configure how new splits should be opened
vim.opt.list = true -- Sets how neovim will display certain whitespace characters in the editor.
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }
vim.opt.inccommand = 'split' -- Preview substitutions live, as you type!
vim.opt.cursorline = true -- Show which line your cursor is on
vim.opt.scrolloff = 10 -- Minimal number of screen lines to keep above and below the cursor.
vim.opt.sidescrolloff = 10 -- Горизонтальный отступ при сайдскроллинге
vim.opt.termguicolors = true -- Поддержка 24-битного цвета
vim.opt.linebreak = true
vim.opt.ttimeoutlen = 10 -- Сократить время ожидания терминальных кодов

vim.loader.enable()
vim.o.laststatus = 3
vim.o.cmdheight = 0

-- Глобальная рамка плавающих окон (hover/signature/LSP) — nvim 0.11+; явные border у blink/snacks/noice её переопределяют
vim.o.winborder = 'rounded'

-- Плавный скролл по визуальным строкам при wrap
vim.opt.smoothscroll = true

-- Граница, по которой переносятся комментарии (gq/gw и авто-перенос по флагу 'c').
-- 80, а не больше: медиана комментариев в этом конфиге — 76 символов, за 83 уходит
-- четверть, и именно этот хвост делает правый край рваным.
--
-- Линейки (colorcolumn) намеренно нет. Границу держит сам авто-перенос, а полоса
-- была бы только напоминанием о нём — при этом висела бы во всех буферах подряд,
-- включая help, oil и пикеры, где ширина ни на что не влияет. Вернуть, если
-- понадобится: `vim.opt.colorcolumn = '+1'` — он относительный и встаёт по
-- textwidth сам, в том числе там, где ftplugin ставит своё (gitcommit — 72).
vim.opt.textwidth = 80

-- 't' (авто-перенос обычного текста) снимаем: ftplugin'ы python и markdown его
-- ставят, и с ненулевым textwidth он начал бы рвать строки КОДА прямо при наборе.
-- Остаётся 'c' — сами переносятся только комментарии; проза и код переносятся
-- вручную по gq/gw. Хук на FileType, а не глобальный set: ftplugin выполняется
-- позже и вернул бы 't' обратно.
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('fo-no-autowrap-text', { clear = true }),
  callback = function()
    vim.opt_local.formatoptions:remove 't'
  end,
})

-- Лимит подсветки для legacy regexp-синтаксиса (:syntax), а не treesitter — тот
-- запускается через vim.treesitter.start (nvim-treesitter.lua) и от synmaxcol не
-- зависит. Опция реально работает только там, где парсера treesitter нет и nvim
-- падает обратно на :syntax (:Man, help и т.п.); от больших файлов вообще
-- защищает snacks.bigfile.
vim.opt.synmaxcol = 300

-- Больше времени на отрисовку, чтобы treesitter не отключался на больших файлах
vim.opt.redrawtime = 2000

-- Отключаем неиспользуемые providers (только Python нужен)
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0

-- Отключаем неиспользуемые built-in плагины
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_2html_plugin = 1
vim.g.loaded_tutor_mode_plugin = 1
vim.g.loaded_spellfile_plugin = 1
-- :Man НЕ отключаем: рабочий инструмент для DevOps (:Man ansible-playbook, :Man ssh_config),
-- и на буферы filetype=man уже рассчитана автокоманда q-close (autocmds.lua)

-- Ограничение shada: 100 файлов истории, 50 строк регистров, 10kb лимит
vim.opt.shada = "'100,<50,s10,h"

-- mason bin в PATH рано — чтобы tree-sitter CLI (для nvim-treesitter main)
-- и прочие инструменты были доступны до загрузки плагинов
vim.env.PATH = vim.fn.stdpath 'data' .. '/mason/bin:' .. vim.env.PATH
