-- Options
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '
vim.g.have_nerd_font = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.mouse = '' -- keyboard-only; hardtime holds the same line
vim.opt.showmode = false -- the mode is already in the status line

vim.schedule(function() -- sync clipboard between OS and Neovim
  vim.opt.clipboard = 'unnamedplus'
end)

vim.opt.numberwidth = 5
vim.opt.fillchars:append { eob = ' ' } -- no ~ on empty lines
vim.opt.breakindent = true
vim.opt.breakindentopt = 'shift:2' -- indent for wrapped long lines (YAML/HCL)
vim.opt.undofile = true
vim.opt.ignorecase = true
vim.opt.smartcase = true -- case-sensitive once the search has a capital or \C
vim.opt.signcolumn = 'yes'
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }
vim.opt.inccommand = 'split' -- live preview of substitutions
vim.opt.cursorline = true
vim.opt.scrolloff = 10
vim.opt.sidescrolloff = 10
vim.opt.termguicolors = true
vim.opt.linebreak = true
vim.opt.ttimeoutlen = 10

vim.loader.enable()
vim.o.laststatus = 3
vim.o.cmdheight = 0

-- global float border (nvim 0.11+); explicit borders in blink/snacks override it
vim.o.winborder = 'rounded'

vim.opt.smoothscroll = true

-- The boundary comments wrap at (gq/gw and auto-wrap through the 'c' flag).
-- NOTE: 80 and not more — the median comment in this config is 76 characters and a
-- quarter run past 83, and that tail is what makes the right edge ragged.
-- NOTE: no colorcolumn on purpose. Auto-wrap already holds the boundary, so the bar would
-- only remind you of it while hanging in every buffer including help, oil and pickers. To
-- bring it back: `vim.opt.colorcolumn = '+1'`, which is relative and follows textwidth
-- even where an ftplugin sets its own (gitcommit uses 72).
vim.opt.textwidth = 80

-- NOTE: 't' (auto-wrapping plain text) is removed because the python and markdown
-- ftplugins set it, and with a non-zero textwidth it would start breaking CODE lines while
-- typing. Only 'c' remains, so comments wrap by themselves and prose is wrapped by hand.
-- A FileType hook rather than a global set: ftplugin runs later and would put 't' back.
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('fo-no-autowrap-text', { clear = true }),
  callback = function()
    vim.opt_local.formatoptions:remove 't'
  end,
})

-- NOTE: synmaxcol limits the legacy regexp syntax engine, not treesitter, which runs
-- through vim.treesitter.start and ignores it. It only matters where no parser exists and
-- nvim falls back to :syntax (:Man, help); big files are handled by snacks.bigfile.
vim.opt.synmaxcol = 300

-- more redraw time so treesitter does not disable itself on large files
vim.opt.redrawtime = 2000

-- unused providers (only Python is needed)
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0

-- unused built-in plugins
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_2html_plugin = 1
vim.g.loaded_tutor_mode_plugin = 1
vim.g.loaded_spellfile_plugin = 1
-- NOTE: :Man stays enabled — it is a working DevOps tool (:Man ansible-playbook), and the
-- q-close autocommand already covers filetype=man buffers.

-- shada: 100 files of history, 50 register lines, 10kb limit
vim.opt.shada = "'100,<50,s10,h"

-- NOTE: mason's bin goes on PATH early so the tree-sitter CLI and friends are available
-- before plugins load.
vim.env.PATH = vim.fn.stdpath 'data' .. '/mason/bin:' .. vim.env.PATH
