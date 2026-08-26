return {
  'stevearc/conform.nvim',
  event = { 'BufWritePre' },
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>f',
      function()
        require('conform').format {
          async = true,
          lsp_format = 'fallback', -- LSP only where no formatter is configured
          timeout_ms = 3000,
        }
      end,
      mode = '',
      desc = '[F]ormat buffer',
    },
    {
      '<leader>tf',
      function()
        vim.g.conform_format_on_save = not (vim.g.conform_format_on_save ~= false)
        local state = vim.g.conform_format_on_save and 'ON' or 'OFF'
        vim.notify('Format on save: ' .. state, vim.log.levels.INFO)
      end,
      mode = '',
      desc = 'Toggle [F]ormat on save',
    },
  },
  opts = {
    notify_no_formatters = false,

    format_on_save = function(bufnr)
      if vim.g.conform_format_on_save == false then
        return false
      end

      local bufname = vim.api.nvim_buf_get_name(bufnr)
      local filetype = vim.bo[bufnr].filetype

      local disable_filetypes = { 'sql', 'text', 'markdown' }
      if vim.tbl_contains(disable_filetypes, filetype) then
        return false
      end

      local max_filesize = 100 * 1024
      local ok, stats = pcall(vim.uv.fs_stat, bufname)
      if ok and stats and stats.size > max_filesize then
        return false
      end

      return {
        timeout_ms = 3000,
        lsp_format = 'fallback',
      }
    end,

    formatters_by_ft = {
      -- ruff fix (imports, lint fixes) then ruff format
      python = { 'ruff_fix', 'ruff_format' },

      lua = { 'stylua' },

      -- Go: goimports first — it rewrites the import block (adding what the
      -- file uses, dropping what it does not) and formats to gofmt on the way
      -- out. gofumpt second because it is a strict superset of gofmt, so the
      -- reverse order would leave gofumpt's rules undone. Both from nixpkgs;
      -- gopls carries gofumpt = true so the LSP path agrees with this one.
      go = { 'goimports', 'gofumpt' },

      -- NOTE: helm templates are left alone — yamlfmt breaks Go templating.
      yaml = function(bufnr)
        local name = vim.api.nvim_buf_get_name(bufnr)
        if vim.bo[bufnr].filetype == 'helm' or name:match '/templates/' then
          return {}
        end
        return { 'yamlfmt' }
      end,

      bash = { 'shfmt' },
      zsh = { 'shfmt' },
      sh = { 'shfmt' },

      -- HCL goes through the LSP (terraform fmt)
      hcl = {},
      terraform = { 'terraform_fmt' },

      dockerfile = {}, -- LSP formatting only

      jsonnet = { 'jsonnetfmt' },
    },

    formatters = {
      -- NOTE: full args, not prepend_args — the built-in ruff_fix already carries
      -- 'check --fix', and prepending duplicated the subcommand into
      -- 'ruff check … check …', which broke.
      ruff_fix = {
        args = {
          'check',
          '--fix',
          '--select',
          'I,F,E,W,UP,B',
          '--force-exclude',
          '--exit-zero',
          '--no-cache',
          '--stdin-filename',
          '$FILENAME',
          '-',
        },
      },

      -- NOTE: no '--respect-gitignore' — that is a flag of 'check' and invalid for 'format'.
      ruff_format = {
        args = {
          'format',
          '--line-length',
          '88',
          '--force-exclude',
          '--stdin-filename',
          '$FILENAME',
          '-',
        },
      },

      -- include_document_start adds the leading '---'; retain_line_breaks_single keeps
      -- blank lines between tasks (collapsing doubles); pad_line_comments=2 matches what
      -- yamllint expects before an inline comment.
      yamlfmt = {
        prepend_args = {
          '-formatter',
          'indent=2,include_document_start=true,retain_line_breaks_single=true,pad_line_comments=2,drop_merge_tag=true',
        },
      },

      shfmt = {
        prepend_args = {
          '-i',
          '2', -- two-space indent
          '-bn', -- binary operators at the start of a line
          '-ci', -- indent case branches
          '-sr', -- redirections after the command
        },
      },
    },
  },
}
