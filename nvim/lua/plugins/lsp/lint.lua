-- nvim-lint [https://github.com/mfussenegger/nvim-lint]
-- Быстрый линтнер работающий без подключения к LSP
return {
  {
    'mfussenegger/nvim-lint',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      local lint = require 'lint'
      lint.linters_by_ft = {
        lua = { 'luacheck' },
        python = { 'ruff', 'mypy' },
        dockerfile = { 'hadolint' },
        -- Web
        -- xml = { 'xmllint' },
        javascript = { 'eslint_d' },
        typescript = { 'eslint_d' },
        html = { 'markuplint' },
        css = { 'stylelint' },
        -- Файлы данных
        json = { 'prettierd' },
        -- Текстовые файлы
        markdown = { 'vale' },
        latex = { 'vale' },
        text = { 'vale' },
        yaml = { 'yamllint' },
      }

      local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
        group = lint_augroup,
        callback = function()
          -- Only run the linter in buffers that you can modify in order to
          -- avoid superfluous noise, notably within the handy LSP pop-ups that
          -- describe the hovered symbol using Markdown.
          if vim.opt_local.modifiable:get() then
            lint.try_lint()
          end
        end,
      })
    end,
  },
}
