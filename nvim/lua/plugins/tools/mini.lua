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

      return '%#Normal#' .. filename .. '%#NormalNC#'
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

    -- Переопределение функции content_provider для mini.statusline
    statusline.setup {
      content = {
        active = function()
          local mode = vim.api.nvim_get_mode().mode
          local mode_name = mode_names[mode] or mode

          local items = {
            '%#Normal#' .. ' ' .. string.upper(mode_name) .. ' ',
            get_fileinfo(),
            get_git_status(),
            '%=', -- Разделитель, центрирует то, что после него
            get_lsp_diagnostic(),
            get_filetype(),
            get_searchcount(),
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
