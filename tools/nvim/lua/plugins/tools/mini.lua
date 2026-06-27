-- Сборник маленьких плагинов которые немало помогают [https://github.com/echasnovski/mini.nvim]
return {
  'echasnovski/mini.nvim',
  config = function()
    -- Better Around/Inside textobjects
    -- Дефолты mini.ai уже дают: a (аргумент), t (тег), q (кавычки), b (скобки)
    local ai = require 'mini.ai'
    ai.setup {
      n_lines = 500,
      custom_textobjects = {
        -- Treesitter-объекты для Python/Go: функция / класс / блок
        -- f: функция через treesitter; fallback на function_call в файлах без парсера
        f = {
          ai.gen_spec.treesitter { a = '@function.outer', i = '@function.inner' },
          ai.gen_spec.function_call(),
        },
        c = ai.gen_spec.treesitter { a = '@class.outer', i = '@class.inner' },
        o = ai.gen_spec.treesitter {
          a = { '@conditional.outer', '@loop.outer', '@block.outer' },
          i = { '@conditional.inner', '@loop.inner', '@block.inner' },
        },
        -- весь буфер: vig / dig / yig
        g = function()
          local last = vim.fn.line '$'
          return {
            from = { line = 1, col = 1 },
            to = { line = last, col = math.max(vim.fn.getline(last):len(), 1) },
          }
        end,
        -- число: cin / din / vin
        n = { '%f[%d]%d+' },
      },
    }

    -- Add/delete/replace surroundings (brackets, quotes, etc.)
    require('mini.surround').setup {
      n_lines = 100, -- многострочные YAML/блоки
      custom_surroundings = {
        -- обёртки под шаблоны (sa<motion><key>):
        j = { output = { left = '{{ ', right = ' }}' } }, -- Helm/Jinja вывод
        J = { output = { left = '{% ', right = ' %}' } }, -- Jinja-блок
        ['$'] = { output = { left = '${', right = '}' } }, -- Terraform-интерполяция
      },
    }

    -- Операторы над текстовыми объектами (gr занят LSP references, поэтому gR)
    require('mini.operators').setup {
      replace = { prefix = 'gR' }, -- заменить объект содержимым регистра
      exchange = { prefix = 'gX' }, -- поменять два объекта местами
    }

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

      return string.format(
        ' %%#DiagnosticError#%s %%#DiagnosticWarn#%s ',
        result.errors,
        result.warnings
      )
    end

    local function get_fileinfo()
      local filename = vim.fn.expand '%' == '' and 'GO BIG OR GO HOME' or vim.fn.expand '%:~:.'
      filename = filename:gsub('^oil://', '')
      filename = ' ' .. filename .. ' '

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

    -- Python окружение (async-запрос версии, кеш по venv)
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

    -- Счётчик поиска без позиции курсора (для Oil: l:c бессмысленно)
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
          -- Терминалы (lazygit/snacks, claude-code, обычный терм): пустой статуслайн.
          -- Путь, filetype, диагностика, позиция курсора для интерактивного TUI — шум.
          if vim.bo.buftype == 'terminal' then
            return ''
          end

          local mode = vim.api.nvim_get_mode().mode
          local mode_name = mode_names[mode] or mode
          local mode_highlight = mode_hl[mode] or 'MiniStatuslineMode'

          -- Oil: минимальный статуслайн без диагностики/filetype/позиции курсора
          if vim.bo.filetype == 'oil' then
            local oil_items = {
              '%#' .. mode_highlight .. '#' .. ' ' .. string.upper(mode_name) .. ' ',
              get_fileinfo(), -- путь текущей директории (oil://...)
              '%=',
              get_macro_recording(),
              get_search_matches_only(), -- только matches при активном поиске
            }
            return statusline.combine_groups(oil_items)
          end

          local items = {
            '%#' .. mode_highlight .. '#' .. ' ' .. string.upper(mode_name) .. ' ',
            get_fileinfo(), -- Имя файла (красное если изменен)
            get_git_status(),
            get_git_diff(), -- Git diff статистика
            '%=', -- Разделитель, центрирует то, что после него
            get_macro_recording(), -- САМОЕ ВАЖНОЕ!
            get_readonly(), -- READONLY если readonly
            -- на узких окнах (<120) прячем второстепенное; на нормальной ширине вид прежний
            statusline.is_truncated(120) and '' or get_python_env(), -- Python окружение
            get_lsp_diagnostic(),
            statusline.is_truncated(120) and '' or get_filetype(),
            get_searchcount(),
          }

          -- combine_groups вместо ручного concat: тот же вывод для строк + аккуратная обработка пустых секций
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
