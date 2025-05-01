return { -- Autoformat
  'stevearc/conform.nvim',
  event = { 'BufWritePre' },
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>f',
      function()
        require('conform').format { async = true, lsp_format = 'prefer' }
      end,
      mode = '',
      desc = '[F]ormat buffer',
    },
    {
      '<leader>tf',
      function()
        if vim.g.conform_format_on_save == nil then
          vim.g.conform_format_on_save = true
        end

        if vim.g.conform_format_on_save then
          -- Отключить автоформатирование при сохранении
          vim.g.conform_format_on_save = false
          require('conform').setup {
            format_on_save = false,
          }
          print 'Автоформатирование при сохранении отключено'
        else
          -- Включить автоформатирование при сохранении
          vim.g.conform_format_on_save = true
          require('conform').setup {
            format_on_save = {
              timeout_ms = 500,
              lsp_fallback = true,
            },
          }
          print 'Автоформатирование при сохранении включено'
        end
      end,
      mode = '',
      desc = '[F]ormat toggl',
    },
  },
  opts = {
    notify_on_error = false,
    format_on_save = function(bufnr)
      -- Disable "format_on_save lsp_fallback" for languages that don't
      -- have a well standardized coding style. You can add additional
      -- languages here or re-enable it for the disabled ones.
      local disable_filetypes = { c = true, cpp = true }
      local lsp_format_opt
      if disable_filetypes[vim.bo[bufnr].filetype] then
        lsp_format_opt = 'never'
      else
        lsp_format_opt = 'prefer'
      end
      return {
        timeout_ms = 500,
        lsp_format = lsp_format_opt,
      }
    end,
    formatters_by_ft = {
      lua = { 'stylua' },
      python = { 'ruff', 'black' },
      bash = { 'beautysh' },
      zsh = { 'beautysh' },
      sh = { 'beautysh' },
      typescript = { 'prettierd' },
      javascript = { 'prettierd' },
      html = { 'prettierd' },
      css = { 'prettierd' },
      yml = { 'yamlfmt' },
      xml = { 'xmlformatter' },
    },
  },
}
