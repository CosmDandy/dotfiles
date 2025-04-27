-- Сборник маленьких плагинов которые немало помогают [https://github.com/echasnovski/mini.nvim]
return {
  'echasnovski/mini.nvim',
  config = function()
    -- TODO: разобраться с этим
    -- Better Around/Inside textobjects
    require('mini.ai').setup { n_lines = 500 }

    -- TODO: разобраться с этим
    -- Add/delete/replace surroundings (brackets, quotes, etc.)
    require('mini.surround').setup()

    -- Улучшенная навигация по тексту [https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-bracketed.md]
    require('mini.bracketed').setup()

    -- Статуслайн снизу [https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-statusline.md]
    local statusline = require 'mini.statusline'
    -- Определение собственных цветов
    local function setup_colors()
      local highlight_groups = {
        StatusNormal = { fg = '#1E1E2E', bg = '#89DCEB', bold = true },   -- Голубой для нормального режима
        StatusInsert = { fg = '#1E1E2E', bg = '#ABE9B3', bold = true },   -- Зеленый для режима вставки
        StatusVisual = { fg = '#1E1E2E', bg = '#FAE3B0', bold = true },   -- Желтый для визуального режима
        StatusReplace = { fg = '#1E1E2E', bg = '#F28FAD', bold = true },  -- Розовый для режима замены
        StatusCommand = { fg = '#1E1E2E', bg = '#C9CBFF', bold = true },  -- Лавандовый для командного режима
        StatusTerminal = { fg = '#1E1E2E', bg = '#BD93F9', bold = true }, -- Фиолетовый для терминала
        Warn = { fg = '#FAE3B0', bg = 'NONE' },                           -- Желтый на темном для предупреждений
        Error = { fg = '#F28FAD', bg = 'NONE' },                          -- Розовый на темном для ошибок
      }

      for group_name, attributes in pairs(highlight_groups) do
        local command = 'highlight ' .. group_name
        if attributes.fg then
          command = command .. ' guifg=' .. attributes.fg
        end
        if attributes.bg then
          command = command .. ' guibg=' .. attributes.bg
        end
        if attributes.bold then
          command = command .. ' gui=bold'
        end

        vim.cmd(command)
      end
    end

    -- Вызываем функцию настройки цветов
    setup_colors()
    -- Определение цветов режимов
    local mode_colors = {
      n = '%#StatusNormal#',
      i = '%#StatusInsert#',
      v = '%#StatusVisual#',
      V = '%#StatusVisual#',
      ['\22'] = '%#StatusVisual#',
      R = '%#StatusReplace#',
      c = '%#StatusCommand#',
      t = '%#StatusTerminal#',
    }

    -- Определение символов режимов
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

      -- return string.format(" %%#Warn#%s %%#Error#%s ",
      --   result.warnings or 0,
      --   result.errors or 0)
      return string.format(' %%#Normal#%s %%#Normal#%s ', result.warnings or 0, result.errors or 0)
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
          -- local mode_color = mode_colors[mode] or '%#Normal#'
          local mode_color = '%#Normal#'
          local mode_name = mode_names[mode] or mode

          local items = {
            mode_color .. ' ' .. string.upper(mode_name) .. ' ',
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
      set_vim_settings = true, -- Установить laststatus и cmdheight
    }

    -- Дополнительные настройки как в вашем коде
    vim.o.laststatus = 3
    vim.o.cmdheight = 0
  end,
}
