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
        -- NOTE: encrypted files are never formatted. yamlfmt folded an ansible-vault file
        -- ($ANSIBLE_VAULT header + hex lines) into a single scalar, which no longer
        -- decrypts, and re-indented the sops: metadata of every *.sops.yaml. Only sops and
        -- ansible-vault may write these.
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        if (lines[1] or ''):match '^%$ANSIBLE_VAULT' then
          return {}
        end
        for _, line in ipairs(lines) do
          if line:match '^sops:' then
            return {}
          end
        end
        return { 'yamlfmt' }
      end,

      bash = { 'shfmt' },
      zsh = { 'shfmt' },
      sh = { 'shfmt' },

      -- HCL goes through the LSP (terraform fmt)
      hcl = {},
      terraform = { 'terraform_fmt' },
      ['terraform-vars'] = { 'terraform_fmt' },

      dockerfile = {}, -- LSP formatting only

      jsonnet = { 'jsonnetfmt' },
    },

    formatters = {
      -- NOTE: ruff_fix/ruff_format keep conform's stock args. The rule set and line
      -- length live in ~/.config/ruff/ruff.toml (tools/ruff), which ruff reads only when
      -- the project has no config — CLI flags here would override the project's own.

      -- include_document_start adds the leading '---'; retain_line_breaks_single keeps
      -- blank lines between tasks (collapsing doubles); pad_line_comments=2 matches what
      -- yamllint expects before an inline comment.
      -- NOTE: scan_folded_as_literal keeps the author's line breaks inside `>` blocks.
      -- Without it yamlfmt joined every folded msg:/fail_msg: into one line of up to
      -- 340 characters — 22 such lines in cloud-lab, each a new line-length finding.
      yamlfmt = {
        prepend_args = {
          '-formatter',
          'indent=2,include_document_start=true,retain_line_breaks_single=true,pad_line_comments=2,drop_merge_tag=true,scan_folded_as_literal=true',
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
