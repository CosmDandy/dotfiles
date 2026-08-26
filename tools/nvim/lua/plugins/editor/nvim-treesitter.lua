return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,
    build = ':TSUpdate',
    -- textobject queries (functions/classes/blocks), consumed through mini.ai
    dependencies = {
      { 'nvim-treesitter/nvim-treesitter-textobjects', branch = 'main' },
    },
    config = function()
      local ts = require 'nvim-treesitter'

      local ensure = {
        'python',
        'sql',
        'json',
        'csv',
        'bash',
        'html',
        'css',
        'javascript',
        'diff',
        'lua',
        'luadoc',
        'markdown',
        'markdown_inline',
        'gitignore',
        'rust',
        'dockerfile',
        'yaml',
        'hcl',
        'terraform',
        'jinja',
        'toml',
        'xml',
        'regex',
        'vim',
        'vimdoc',
        -- go family: gomod/gosum cover go.mod and go.sum, gowork the
        -- multi-module workspace file. gotmpl below is unrelated — it is
        -- the template dialect helm charts are written in.
        'go',
        'gomod',
        'gosum',
        'gowork',
        'gotmpl',
        'helm',
        'jsonnet',
        -- the machine's own configuration language; without it flake.nix opened as text
        'nix',
        -- commit messages and interactive rebase are written here too
        'gitcommit',
        'git_rebase',
      }
      -- NOTE: asynchronous in an interactive session so startup is not delayed, but
      -- headless (image build, home-manager activation) it WAITS — otherwise nvim exits
      -- before compilation finishes and a random subset of parsers lands in the image.
      pcall(function()
        local handle = ts.install(ensure)
        if handle and #vim.api.nvim_list_uis() == 0 then
          handle:wait(600000)
        end
      end)

      -- NOTE: ft → parser where the names differ, or language.get_lang returns nil and
      -- there is no highlighting at all.
      pcall(vim.treesitter.language.register, 'jinja', { 'jinja2', 'htmldjango' })

      -- Highlighting and folds come from core vim.treesitter, indentation from the plugin.
      -- NOTE: the plugin stays ONLY as a parser installer and a source of queries — nvim
      -- core ships 7 parsers and no installer, so it cannot be dropped entirely.

      -- Incremental selection by the parse tree: <C-space> expands to the next node up,
      -- <BS> steps back.
      -- NOTE: hand-written because the incremental_selection module was cut from
      -- nvim-treesitter along with the old module system on the main branch, and upstream
      -- offered no replacement.
      -- NOTE: the stack is per buffer and reset when visual mode ends, or the next
      -- expansion would continue from the previous selection's node.
      local sel_stack = {}
      -- NOTE: "we are changing the mode ourselves" flag. Without it the autocommand below
      -- read the mode switch inside select_range as the user leaving visual and cleared
      -- the stack — every second expansion restarted from the cursor and the selection
      -- collapsed to a point instead of moving to the parent.
      local ts_internal = false

      local function select_range(sr, sc, er, ec)
        -- NOTE: treesitter ranges are zero-indexed and end-exclusive while visual mode is
        -- one-indexed and inclusive. ec == 0 means the node ends at the very start of line
        -- er, so the last included character is at the end of the previous line.
        if ec == 0 and er > 0 then
          er = er - 1
          ec = #vim.fn.getline(er + 1)
        end
        ts_internal = true
        if vim.fn.mode():match '[vV\22]' then
          vim.cmd 'normal! \27'
        end
        vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
        vim.cmd 'normal! v'
        vim.api.nvim_win_set_cursor(0, { er + 1, math.max(ec - 1, 0) })
        ts_internal = false
      end

      local function ts_expand()
        local buf = vim.api.nvim_get_current_buf()
        local st = sel_stack[buf]
        local node
        if not st or #st == 0 then
          st = {}
          sel_stack[buf] = st
          node = vim.treesitter.get_node()
        else
          -- NOTE: climb until the range actually changes — nested nodes often share one,
          -- and such a step would look like the key doing nothing.
          local prev = st[#st]
          node = prev
          repeat
            node = node:parent()
          until not node or not vim.deep_equal({ node:range() }, { prev:range() })
        end
        if not node then
          return
        end
        table.insert(st, node)
        select_range(node:range())
      end

      local function ts_shrink()
        local buf = vim.api.nvim_get_current_buf()
        local st = sel_stack[buf]
        if not st or #st < 2 then
          return
        end
        table.remove(st)
        select_range(st[#st]:range())
      end

      vim.keymap.set({ 'n', 'x' }, '<C-space>', ts_expand, { desc = 'Расширить выделение по дереву' })
      vim.keymap.set('x', '<BS>', ts_shrink, { desc = 'Сузить выделение по дереву' })

      vim.api.nvim_create_autocmd('ModeChanged', {
        group = vim.api.nvim_create_augroup('treesitter-incremental', { clear = true }),
        pattern = '[vV\22]*:[^vV\22]*',
        callback = function(args)
          if not ts_internal then
            sel_stack[args.buf] = nil
          end
        end,
      })

      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('treesitter-features', { clear = true }),
        callback = function(args)
          local buf = args.buf
          local ft = vim.bo[buf].filetype
          if ft == '' then
            return
          end
          local lang = vim.treesitter.language.get_lang(ft) or ft
          -- highlighting only when the parser is available (pcall guards the first run)
          if pcall(vim.treesitter.start, buf, lang) then
            -- NOTE: vim.wo[0][0] is window-local-for-buffer, so these do not leak into
            -- other windows showing another file.
            vim.wo[0][0].foldmethod = 'expr'
            vim.wo[0][0].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
            vim.wo[0][0].foldlevel = 99
            -- indentation from nvim-treesitter (marked experimental upstream)
            vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },
}
