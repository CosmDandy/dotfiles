-- nvim-lint [https://github.com/mfussenegger/nvim-lint]
-- Быстрый линтнер работающий без подключения к LSP
return {
  {
    'mfussenegger/nvim-lint',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      local lint = require 'lint'
      local warned = {}
      lint.linters_by_ft = {
        lua = { 'luacheck' },
        python = { 'ruff' },
        dockerfile = { 'hadolint' },
        yaml = { 'yamllint' },
        ['yaml.ansible'] = { 'ansible_lint' },
        terraform = { 'tflint' },
      }

      -- mypy медленный — гоняем только при сохранении, не на каждый BufEnter/InsertLeave
      vim.api.nvim_create_autocmd('BufWritePost', {
        group = vim.api.nvim_create_augroup('lint-mypy', { clear = true }),
        pattern = '*.py',
        callback = function()
          if vim.fn.executable 'mypy' == 1 then
            lint.try_lint 'mypy'
          end
        end,
      })

      local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
      local timer = assert((vim.uv or vim.loop).new_timer())
      -- BufReadPost (один раз на открытие) вместо BufEnter (каждый фокус окна);
      -- debounce 100мс схлопывает серию событий в один запуск линтеров
      vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost', 'InsertLeave', 'TextChanged' }, {
        group = lint_augroup,
        callback = function()
          timer:stop()
          timer:start(100, 0, vim.schedule_wrap(function()
            if not vim.opt_local.modifiable:get() then
              return
            end
            local ft_linters = lint.linters_by_ft[vim.bo.filetype] or {}
            local available, missing = {}, {}
            for _, name in ipairs(ft_linters) do
              local linter = lint.linters[name]
              local cmd = (type(linter) == 'table' and linter.cmd) or name
              if vim.fn.executable(cmd) == 1 then
                table.insert(available, name)
              else
                table.insert(missing, name)
              end
            end
            local new_missing = vim.tbl_filter(function(n) return not warned[n] end, missing)
            if #new_missing > 0 then
              for _, n in ipairs(new_missing) do warned[n] = true end
              vim.notify('Linters not installed: ' .. table.concat(new_missing, ', '), vim.log.levels.WARN, { title = 'nvim-lint' })
            end
            if #available > 0 then
              lint.try_lint(available)
            end
          end))
        end,
      })
    end,
  },
}
