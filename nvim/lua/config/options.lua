-- Options
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '
vim.g.have_nerd_font = true -- Set to true if you have a Nerd Font installed and selected in the terminal
vim.opt.number = true       -- Make line numbers default
vim.opt.relativenumber = true
vim.opt.mouse = 'a'         -- Enable mouse mode, can be useful for resizing splits for example!
vim.opt.showmode = false    -- Don't show the mode, since it's already in the status line

vim.schedule(function()     -- Sync clipboard between OS and Neovim.
  vim.opt.clipboard = 'unnamedplus'
end)

vim.opt.numberwidth = 5
vim.opt.fillchars:append { eob = ' ' } -- Убираем символы тильды (~) в пустых строках
vim.opt.breakindent = true             -- Enable break indent
vim.opt.undofile = true                -- Save undo history
vim.opt.ignorecase = true
vim.opt.smartcase = true               -- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.opt.signcolumn = 'yes'             -- Keep signcolumn on by default
vim.opt.updatetime = 250               -- Decrease update time
vim.opt.timeoutlen = 300               -- Decrease mapped sequence wait time
vim.opt.splitright = true
vim.opt.splitbelow = true              -- Configure how new splits should be opened
vim.opt.list = true                    -- Sets how neovim will display certain whitespace characters in the editor.
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }
vim.opt.inccommand = 'split'           -- Preview substitutions live, as you type!
vim.opt.cursorline = true              -- Show which line your cursor is on
vim.opt.scrolloff = 10                 -- Minimal number of screen lines to keep above and below the cursor.
vim.opt.sidescrolloff = 10             -- Горизонтальный отступ при сайдскроллинге
vim.opt.termguicolors = true           -- Поддержка 24-битного цвета
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.encoding = "utf-8"
vim.opt.fileencoding = "utf-8"
vim.opt.ambiwidth = "single"
vim.opt.ttimeoutlen = 10 -- Сократить время ожидания терминальных кодов


vim.loader.enable()
vim.o.laststatus = 3
vim.o.cmdheight = 0
