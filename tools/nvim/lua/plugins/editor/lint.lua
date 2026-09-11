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

      -- ansible-lint prints paths relative to its own cwd (the ansible.cfg directory, see
      -- below), while the errorformat parser resolves them against nvim's :pwd and drops
      -- whatever lands in another buffer — every finding vanished. Anchor them to the
      -- linter's cwd first.
      local ansible_parser = lint.linters.ansible_lint.parser
      lint.linters.ansible_lint.parser = function(output, bufnr, linter_cwd)
        output = output:gsub('[^\n]+', function(line)
          if linter_cwd and line:match '^[^/%s][^:]*:%d+' then
            return linter_cwd .. '/' .. line
          end
        end)
        return ansible_parser(output, bufnr, linter_cwd)
      end

      local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
      local timer = assert((vim.uv or vim.loop).new_timer())
      -- NOTE: linters without stdin (ansible-lint, tflint) read the file from disk, so on
      -- TextChanged they would lint the stale saved copy and pay a full process start per
      -- edit. They run on read and write only; the flag survives the debounce, so a
      -- BufWritePost+TextChanged burst still gets its disk run.
      local disk_due = false
      -- BufReadPost fires once per open, unlike BufEnter which fires on every window
      -- focus; the 100ms debounce collapses a burst of events into one lint run
      vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost', 'InsertLeave', 'TextChanged' }, {
        group = lint_augroup,
        callback = function(args)
          if args.event == 'BufReadPost' or args.event == 'BufWritePost' then
            disk_due = true
          end
          timer:stop()
          timer:start(
            100,
            0,
            vim.schedule_wrap(function()
              local with_disk = disk_due
              disk_due = false
              if not vim.opt_local.modifiable:get() then
                return
              end
              local ft = vim.bo.filetype
              -- a compound filetype without its own entry (yaml.docker-compose,
              -- yaml.helm-values) takes its base's linters; yaml.ansible has its own
              local ft_linters = lint.linters_by_ft[ft] or lint.linters_by_ft[vim.split(ft, '.', { plain = true })[1]] or {}
              -- a sops file is ciphertext: yamllint only reported line-length on its values
              if vim.tbl_contains(ft_linters, 'yamllint') and vim.fn.search('^sops:', 'nw') > 0 then
                ft_linters = vim.tbl_filter(function(n)
                  return n ~= 'yamllint'
                end, ft_linters)
              end
              local available, missing = {}, {}
              for _, name in ipairs(ft_linters) do
                local linter = lint.linters[name]
                local cmd = (type(linter) == 'table' and linter.cmd) or name
                local reads_disk = type(linter) == 'table' and not linter.stdin
                if vim.fn.executable(cmd) ~= 1 then
                  table.insert(missing, name)
                elseif with_disk or not reads_disk then
                  table.insert(available, name)
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
              -- NOTE: ansible-lint resolves roles through ansible.cfg, which a repo may keep
              -- in a subdirectory (ansible/); run from the repo root it reported every role
              -- as missing. It runs from the nearest directory that has one.
              local rest = {}
              local ansible_root = vim.fs.root(0, 'ansible.cfg')
              for _, name in ipairs(available) do
                if name == 'ansible_lint' and ansible_root then
                  lint.try_lint(name, { cwd = ansible_root })
                else
                  table.insert(rest, name)
                end
              end
              if #rest > 0 then
                lint.try_lint(rest)
              end
            end)
          )
        end,
      })
    end,
  },
}
