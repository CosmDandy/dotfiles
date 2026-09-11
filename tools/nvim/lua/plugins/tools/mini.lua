-- A collection of small plugins: https://github.com/echasnovski/mini.nvim
return {
  'echasnovski/mini.nvim',
  config = function()
    -- NOTE: only the statusline is needed for the first screen. The editing modules
    -- are set up on VeryLazy, right after it — together they were most of mini's
    -- ~10ms on every start (measured), and nothing can use them before a keypress.
    vim.api.nvim_create_autocmd('User', {
      pattern = 'VeryLazy',
      once = true,
      callback = function()
        -- Around/inside textobjects. The mini.ai defaults already cover a (argument),
        -- t (tag), q (quotes) and b (brackets).
        local ai = require 'mini.ai'
        ai.setup {
          n_lines = 500,
          custom_textobjects = {
            -- f falls back to function_call in files without a treesitter parser
            f = {
              ai.gen_spec.treesitter { a = '@function.outer', i = '@function.inner' },
              ai.gen_spec.function_call(),
            },
            c = ai.gen_spec.treesitter { a = '@class.outer', i = '@class.inner' },
            o = ai.gen_spec.treesitter {
              a = { '@conditional.outer', '@loop.outer', '@block.outer' },
              i = { '@conditional.inner', '@loop.inner', '@block.inner' },
            },
            -- the whole buffer: vig / dig / yig
            g = function()
              local last = vim.fn.line '$'
              return {
                from = { line = 1, col = 1 },
                to = { line = last, col = math.max(vim.fn.getline(last):len(), 1) },
              }
            end,
            -- a number: cin / din / vin
            n = { '%f[%d]%d+' },
          },
        }

        -- NOTE: the gz prefix instead of the default s — s belongs to flash, and typing
        -- s followed by a/d/r fired surround instead of a jump.
        require('mini.surround').setup {
          mappings = {
            add = 'gza',
            delete = 'gzd',
            find = 'gzf',
            find_left = 'gzF',
            highlight = 'gzh',
            replace = 'gzr',
            update_n_lines = 'gzn',
          },
          n_lines = 100, -- multi-line YAML blocks
          custom_surroundings = {
            j = { output = { left = '{{ ', right = ' }}' } }, -- Helm/Jinja output
            J = { output = { left = '{% ', right = ' %}' } }, -- Jinja block
            ['$'] = { output = { left = '${', right = '}' } }, -- Terraform interpolation
          },
        }

        -- Replaces nvim-autopairs; brackets after a completion are added by blink.cmp itself.
        require('mini.pairs').setup()
        -- pairs make no sense in the snacks picker input
        vim.api.nvim_create_autocmd('FileType', {
          pattern = 'snacks_picker_input',
          group = vim.api.nvim_create_augroup('minipairs-disable', { clear = true }),
          callback = function(args)
            vim.b[args.buf].minipairs_disable = true
          end,
        })

        -- NOTE: gR/gX because gr is taken by LSP references.
        require('mini.operators').setup {
          replace = { prefix = 'gR' },
          exchange = { prefix = 'gX' },
        }

        require('mini.bracketed').setup()

        -- ga{motion} + a separator aligns into columns, gA does the same with a preview —
        -- trailing comments and value tables line up.
        -- NOTE: this shadows the built-in ga (character code); :ascii and g8 still do that.
        require('mini.align').setup()

        -- NOTE: cursor animation only. scroll is handled by snacks.scroll, and
        -- open/close/resize fight with snacks' floating windows (picker, input, notifier)
        -- and flicker every time one opens.
        local animate = require 'mini.animate'
        animate.setup {
          cursor = {
            timing = animate.gen_timing.linear { duration = 80, unit = 'total' },
          },
          scroll = { enable = false },
          resize = { enable = false },
          open = { enable = false },
          close = { enable = false },
        }
      end,
    })

    local statusline = require 'mini.statusline'

    local mode_names = {
      n = 'RW',
      no = 'RO',
      v = '**',
      V = '**',
      ['\22'] = '**',
      s = 'S',
      S = 'SL',
      ['\19'] = 'SB',
      i = '**',
      ic = '**',
      R = 'RA',
      Rv = 'RV',
      c = 'VIEX',
      cv = 'VIEX',
      ce = 'EX',
      r = 'r',
      rm = 'r',
      ['r?'] = 'r',
      ['!'] = '!',
      t = '',
    }

    local mode_hl = {
      n = 'MiniStatuslineModeNormal',
      no = 'MiniStatuslineModeNormal',
      v = 'MiniStatuslineModeVisual',
      V = 'MiniStatuslineModeVisual',
      ['\22'] = 'MiniStatuslineModeVisual',
      s = 'MiniStatuslineModeVisual',
      S = 'MiniStatuslineModeVisual',
      ['\19'] = 'MiniStatuslineModeVisual',
      i = 'MiniStatuslineModeInsert',
      ic = 'MiniStatuslineModeInsert',
      R = 'MiniStatuslineModeReplace',
      Rv = 'MiniStatuslineModeReplace',
      c = 'MiniStatuslineModeCommand',
      cv = 'MiniStatuslineModeCommand',
      ce = 'MiniStatuslineModeCommand',
      r = 'MiniStatuslineModeCommand',
      rm = 'MiniStatuslineModeCommand',
      ['r?'] = 'MiniStatuslineModeCommand',
      ['!'] = 'MiniStatuslineModeCommand',
      t = 'MiniStatuslineMode',
    }

    local function get_git_status()
      local branch = vim.b.gitsigns_status_dict or { head = '' }
      local has_head = branch.head ~= ''

      return has_head and string.format('%s ', branch.head) or ''
    end

    local function get_lsp_diagnostic()
      if not rawget(vim, 'lsp') then
        return ''
      end

      local function get_severity(s)
        return #vim.diagnostic.get(0, { severity = s })
      end

      local result = {
        errors = get_severity(vim.diagnostic.severity.ERROR),
        warnings = get_severity(vim.diagnostic.severity.WARN),
      }

      return string.format(' %%#DiagnosticError#%s %%#DiagnosticWarn#%s ', result.errors, result.warnings)
    end

    local function get_fileinfo()
      local filename = vim.fn.expand '%' == '' and 'GO BIG OR GO HOME' or vim.fn.expand '%:~:.'
      filename = filename:gsub('^oil://', '')
      filename = ' ' .. filename .. ' '

      -- red when modified, same colour as the filetype when not
      local hl = vim.bo.modified and '%#ModifiedIndicator#' or '%#NormalNC#'
      return hl .. filename .. '%#Normal#'
    end

    local function get_filetype()
      return '%#NormalNC#' .. vim.bo.filetype
    end

    local function get_searchcount()
      if vim.v.hlsearch == 0 then
        return '%#Normal# %l:%c '
      end

      local ok, count = pcall(vim.fn.searchcount, { recompute = false })
      if not ok or count.current == nil or count.total == 0 then
        return '%#Normal# %l:%c '
      end

      if count.incomplete == 1 then
        return '?/?'
      end

      local too_many = string.format('>%d', count.maxcount)
      local total = count.total > count.maxcount and too_many or count.total

      return '%#Normal#' .. string.format(' %s matches ', total)
    end

    local function get_macro_recording()
      local recording = vim.fn.reg_recording()
      if recording == '' then
        return ''
      end
      return '%#MacroRecording#' .. ' @' .. recording .. ' '
    end

    local function get_readonly()
      if vim.bo.readonly then
        return '%#ReadonlyIndicator# READONLY %#Normal#'
      end
      return ''
    end

    local function get_git_diff()
      local signs = vim.b.gitsigns_status_dict
      if not signs then
        return ''
      end

      local added = signs.added or 0
      local changed = signs.changed or 0
      local removed = signs.removed or 0

      if added == 0 and changed == 0 and removed == 0 then
        return ''
      end

      local parts = {}
      if added > 0 then
        table.insert(parts, '%#GitSignsAdd#+' .. added)
      end
      if changed > 0 then
        table.insert(parts, '%#GitSignsChange#~' .. changed)
      end
      if removed > 0 then
        table.insert(parts, '%#GitSignsDelete#-' .. removed)
      end

      return table.concat(parts, ' ') .. '%#Normal# '
    end

    -- NOTE: the version is fetched asynchronously and cached per venv — a synchronous
    -- call would run on every statusline redraw.
    local python_version_cache = {}
    local function get_python_env()
      local venv = vim.env.VIRTUAL_ENV
      if not venv then
        return ''
      end

      local venv_name = vim.fn.fnamemodify(venv, ':t')

      if python_version_cache[venv] == nil then
        python_version_cache[venv] = 'pending'
        vim.system({ venv .. '/bin/python', '--version' }, { text = true }, function(out)
          local stdout = (out.stdout or '') .. (out.stderr or '')
          local version = stdout:match 'Python (%d+%.%d+%.%d+)' or stdout:match 'Python (%d+%.%d+)' or '?'
          vim.schedule(function()
            python_version_cache[venv] = version
            vim.cmd 'redrawstatus'
          end)
        end)
      end

      local version = python_version_cache[venv]
      if version == 'pending' then
        return '%#NormalNC#' .. venv_name
      end
      return '%#NormalNC#' .. venv_name .. ' (' .. version .. ')'
    end

    -- search count without the cursor position, for Oil where l:c is meaningless
    local function get_search_matches_only()
      if vim.v.hlsearch == 0 then
        return ''
      end

      local ok, count = pcall(vim.fn.searchcount, { recompute = false })
      if not ok or count.current == nil or count.total == 0 then
        return ''
      end

      if count.incomplete == 1 then
        return '%#Normal# ?/? '
      end

      local too_many = string.format('>%d', count.maxcount)
      local total = count.total > count.maxcount and too_many or count.total

      return '%#Normal#' .. string.format(' %s matches ', total)
    end

    statusline.setup {
      content = {
        active = function()
          -- Terminals (lazygit, claude-code, a plain shell) get an empty statusline: path,
          -- filetype, diagnostics and cursor position are noise for an interactive TUI.
          if vim.bo.buftype == 'terminal' then
            return ''
          end

          local mode = vim.api.nvim_get_mode().mode
          local mode_name = mode_names[mode] or mode
          local mode_highlight = mode_hl[mode] or 'MiniStatuslineMode'

          -- With laststatus=3 the global statusline reflects the focused float, so an
          -- open snacks picker/input would show its own filetype and diagnostics —
          -- keep only the mode, name placeholder and cursor position.
          if vim.bo.filetype:find '^snacks_' then
            local snacks_items = {
              '%#' .. mode_highlight .. '#' .. ' ' .. string.upper(mode_name) .. ' ',
              get_fileinfo(),
              '%=',
              '%#Normal# %l:%c ',
            }
            return statusline.combine_groups(snacks_items)
          end

          -- Oil gets a minimal line without diagnostics, filetype or cursor position
          if vim.bo.filetype == 'oil' then
            local oil_items = {
              '%#' .. mode_highlight .. '#' .. ' ' .. string.upper(mode_name) .. ' ',
              get_fileinfo(),
              '%=',
              get_macro_recording(),
              get_search_matches_only(),
            }
            return statusline.combine_groups(oil_items)
          end

          local items = {
            '%#' .. mode_highlight .. '#' .. ' ' .. string.upper(mode_name) .. ' ',
            get_fileinfo(),
            get_git_status(),
            get_git_diff(),
            '%=', -- centres everything after it
            get_macro_recording(),
            get_readonly(),
            -- narrow windows drop the secondary parts; at normal width nothing changes
            statusline.is_truncated(120) and '' or get_python_env(),
            get_lsp_diagnostic(),
            statusline.is_truncated(120) and '' or get_filetype(),
            get_searchcount(),
          }

          -- combine_groups rather than a manual concat: same output plus tidy handling of
          -- empty sections
          return statusline.combine_groups(items)
        end,

        inactive = function()
          return '%#NormalNC# %f'
        end,
      },

      set_vim_settings = true,
    }
  end,
}
