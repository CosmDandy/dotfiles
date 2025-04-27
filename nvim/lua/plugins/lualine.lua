return {
  {
    'nvim-lualine/lualine.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function()
      -- require('lualine').setup()
      -- Lualine конфигурация
      local lualine = require('lualine')

      -- Цвета для режимов
      local mode_colors = {
        n = '#89DCEB',     -- Normal
        i = '#ABE9B3',     -- Insert
        v = '#FAE3B0',     -- Visual
        [''] = '#FAE3B0', -- Visual block
        V = '#FAE3B0',     -- Visual line
        c = '#C9CBFF',     -- Command
        R = '#F28FAD',     -- Replace
        t = '#BD93F9',     -- Terminal
      }

      -- Функция для определения цвета по режиму
      local function mode_color()
        local mode = vim.fn.mode()
        return { fg = '#1E1E2E', bg = mode_colors[mode] or '#FFFFFF', gui = 'bold' }
      end

      -- Функция для отображения текущего режима
      local function mode_name()
        local map = {
          n = 'RW',
          no = 'RO',
          i = '**',
          ic = '**',
          v = '**',
          V = '**',
          [''] = '**',
          c = 'VIEX',
          ce = 'EX',
          R = 'RA',
          Rv = 'RV',
          s = 'S',
          S = 'SL',
          [''] = 'SB',
          t = '',
          ['!'] = '!',
        }
        return (map[vim.fn.mode()] or vim.fn.mode())
      end

      -- Гит статус (ветка)
      local function git_branch()
        local gitsigns = vim.b.gitsigns_status_dict
        return gitsigns and gitsigns.head or ''
      end

      -- Диагностика LSP
      local function lsp_diagnostics()
        local errors = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })
        local warns = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN })
        return string.format(' %d   %d', warns, errors)
      end

      -- Название файла
      local function file_name()
        local filename = vim.fn.expand('%:t')
        if filename == '' then
          filename = 'GO BIG OR GO HOME'
        end
        return filename
      end

      -- Подсчет поиска
      local function search_count()
        if vim.v.hlsearch == 0 then
          return ''
        end

        local ok, sc = pcall(vim.fn.searchcount, { recompute = true })
        if not ok or not sc.current or sc.total == 0 then
          return ''
        end

        local total = sc.total > sc.maxcount and string.format('>%d', sc.maxcount) or sc.total
        return string.format('[%s]', total)
      end

      -- Настройка lualine
      lualine.setup({
        options = {
          theme = 'auto',
          component_separators = '',
          section_separators = '',
          disabled_filetypes = {},
          globalstatus = true,
        },
        sections = {
          lualine_a = {
            {
              mode_name,
              color = mode_color,
              padding = { left = 1, right = 1 },
            },
          },
          lualine_b = {
            { file_name, color = { fg = '#1E1E2E' } },
          },
          lualine_c = {
            { git_branch, color = { fg = '#89DCEB', gui = 'bold' } },
          },
          lualine_x = {
            { lsp_diagnostics, color = { fg = '#F28FAD' } },
            { search_count,    color = { fg = '#FAE3B0' } },
          },
          lualine_y = {
            { 'filetype', color = { fg = '#C9CBFF' } },
          },
          lualine_z = {
            { 'location' },
          },
        },
        inactive_sections = {
          lualine_a = {},
          lualine_b = {},
          lualine_c = { { 'filename', color = { fg = '#666666' } } },
          lualine_x = {},
          lualine_y = {},
          lualine_z = {},
        },
      })
    end
  },
}
