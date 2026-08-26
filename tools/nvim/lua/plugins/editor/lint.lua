-- nvim-lint [https://github.com/mfussenegger/nvim-lint]
-- A fast linter that works without an LSP connection.
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

      -- NOTE: mypy is slow, so it runs on save only, not on every BufEnter/InsertLeave
      vim.api.nvim_create_autocmd('BufWritePost', {
        group = vim.api.nvim_create_augroup('lint-mypy', { clear = true }),
        pattern = '*.py',
        callback = function()
          if vim.fn.executable 'mypy' == 1 then
            lint.try_lint 'mypy'
          end
        end,
      })

      -- golangci-lint runs a dozen analyzers over the whole package, so it
      -- belongs on save rather than in linters_by_ft — there it would inherit
      -- the TextChanged trigger below and fire on every keystroke. Same reason
      -- mypy is handled separately above.
      vim.api.nvim_create_autocmd('BufWritePost', {
        group = vim.api.nvim_create_augroup('lint-golangci', { clear = true }),
        pattern = '*.go',
        callback = function()
          if vim.fn.executable 'golangci-lint' == 1 then
            lint.try_lint 'golangcilint'
          end
        end,
      })

      local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
      local timer = assert((vim.uv or vim.loop).new_timer())
      -- BufReadPost fires once per open, unlike BufEnter which fires on every window
      -- focus; the 100ms debounce collapses a burst of events into one lint run
      vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost', 'InsertLeave', 'TextChanged' }, {
        group = lint_augroup,
        callback = function()
          timer:stop()
          timer:start(
            100,
            0,
            vim.schedule_wrap(function()
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
              local new_missing = vim.tbl_filter(function(n)
                return not warned[n]
              end, missing)
              if #new_missing > 0 then
                for _, n in ipairs(new_missing) do
                  warned[n] = true
                end
                vim.notify('Linters not installed: ' .. table.concat(new_missing, ', '), vim.log.levels.WARN, { title = 'nvim-lint' })
              end
              if #available > 0 then
                lint.try_lint(available)
              end
            end)
          )
        end,
      })
    end,
  },
}
