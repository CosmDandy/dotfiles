-- Сборник маленьких плагинов которые немало помогают [https://github.com/echasnovski/mini.nvim]
return {
  'echasnovski/mini.nvim',
  config = function()
    -- Better Around/Inside textobjects
    require('mini.ai').setup { n_lines = 500 }

    -- Add/delete/replace surroundings (brackets, quotes, etc.)
    require('mini.surround').setup()

    -- Улучшенная навигация по тексту [https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-bracketed.md]
    require('mini.bracketed').setup()

    -- Статуслайн снизу [https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-statusline.md]
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

    -- Маппинг режимов на highlight groups
    local mode_hl = {
      n = 'MiniStatuslineModeNormal', -- Normal
      no = 'MiniStatuslineModeNormal', -- Operator-pending
      v = 'MiniStatuslineModeVisual', -- Visual
      V = 'MiniStatuslineModeVisual', -- Visual Line
      ['\22'] = 'MiniStatuslineModeVisual', -- Visual Block
      s = 'MiniStatuslineModeVisual', -- Select
      S = 'MiniStatuslineModeVisual', -- Select Line
      ['\19'] = 'MiniStatuslineModeVisual', -- Select Block
      i = 'MiniStatuslineModeInsert', -- Insert
      ic = 'MiniStatuslineModeInsert', -- Insert completion
      R = 'MiniStatuslineModeReplace', -- Replace
      Rv = 'MiniStatuslineModeReplace', -- Virtual Replace
      c = 'MiniStatuslineModeCommand', -- Command
      cv = 'MiniStatuslineModeCommand', -- Vim Ex
      ce = 'MiniStatuslineModeCommand', -- Ex
      r = 'MiniStatuslineModeCommand', -- Prompt
      rm = 'MiniStatuslineModeCommand', -- More
      ['r?'] = 'MiniStatuslineModeCommand', -- Confirm
      ['!'] = 'MiniStatuslineModeCommand', -- Shell
      t = 'MiniStatuslineMode', -- Terminal
    }

    local function get_git_status()
      local branch = vim.b.gitsigns_status_dict or { head = '' }
      local is_head_empty = branch.head ~= ''

      return is_head_empty and string.format('%s ', branch.head) or ''
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

      return string.format(' %%#Normal#%s %%#Normal#%s ', result.errors or 0, result.warnings or 0)
    end

    local function get_fileinfo()
      local filename = vim.fn.expand '%' == '' and 'GO BIG OR GO HOME' or vim.fn.expand '%:t'

      if filename ~= ' nyoom-nvim ' then
        filename = ' ' .. filename .. ' '
      end

      -- Красное имя файла если модифицирован, такое же как filetype если нет
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

      local ok, count = pcall(vim.fn.searchcount, { recompute = true })
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

    -- Индикатор записи макроса (самое важное!)
    local function get_macro_recording()
      local recording = vim.fn.reg_recording()
      if recording == '' then
        return ''
      end
      return '%#MacroRecording#' .. ' @' .. recording .. ' '
    end

    -- Readonly флаг
    local function get_readonly()
      if vim.bo.readonly then
        return '%#ReadonlyIndicator# READONLY %#Normal#'
      end
      return ''
    end

    -- Git diff статистика
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

    -- Python окружение
    local function get_python_env()
      local venv = vim.env.VIRTUAL_ENV
      if not venv then
        return ''
      end

      local venv_name = vim.fn.fnamemodify(venv, ':t')
      return '%#Normal# ' .. venv_name .. ' '
    end

    -- Переопределение функции content_provider для mini.statusline
    statusline.setup {
      content = {
        active = function()
          local mode = vim.api.nvim_get_mode().mode
          local mode_name = mode_names[mode] or mode
          local mode_highlight = mode_hl[mode] or 'MiniStatuslineMode'

          local items = {
            '%#' .. mode_highlight .. '#' .. ' ' .. string.upper(mode_name) .. ' ',
            get_fileinfo(), -- Имя файла (красное если изменен)
            get_git_status(),
            get_git_diff(), -- Git diff статистика
            '%=', -- Разделитель, центрирует то, что после него
            get_macro_recording(), -- САМОЕ ВАЖНОЕ!
            get_readonly(), -- READONLY если readonly
            get_lsp_diagnostic(),
            get_filetype(),
            get_searchcount(),
            get_python_env(), -- Python окружение
          }

          return table.concat(items)
        end,

        inactive = function()
          return '%#NormalNC# %f'
        end,
      },

      use_icons = true,
      set_vim_settings = true,
    }
  end,
}
