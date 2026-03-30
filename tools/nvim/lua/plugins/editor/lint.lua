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
        python = { 'ruff', 'mypy' },
        dockerfile = { 'hadolint' },
        yaml = { 'yamllint' },
        ['yaml.ansible'] = { 'ansible-lint' },
      }

      local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
        group = lint_augroup,
        callback = function()
          if vim.opt_local.modifiable:get() then
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
          end
        end,
      })
    end,
  },
}
