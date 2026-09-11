-- Filetypes left alone on save; :FormatOnSaveToggle [ft] flips one for the session.
-- NOTE: python is off by default: ruff reads ~/.config/ruff/ruff.toml wherever a project
-- has no config of its own, and a save re-sorted imports in colleagues' code.
local off_on_save = { python = true }

return {
  'stevearc/conform.nvim',
  event = { 'BufWritePre' },
  cmd = { 'ConformInfo' },
  init = function()
    vim.api.nvim_create_user_command('FormatOnSaveToggle', function(args)
      local ft = args.args ~= '' and args.args or vim.bo.filetype
      off_on_save[ft] = not off_on_save[ft] or nil
      vim.notify(('Format on save for %s: %s'):format(ft, off_on_save[ft] and 'OFF' or 'ON'), vim.log.levels.INFO)
    end, { nargs = '?', complete = 'filetype', desc = 'Toggle format on save for a filetype' })
  end,
  keys = {
    {
      '<leader>f',
      function()
        require('conform').format {
          async = true,
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

    -- LSP only where no formatter is configured.
    -- NOTE: here and not in the format() calls: conform fills in a filetype's own
    -- lsp_format only when the call leaves it unset, and the yaml function below needs
    -- 'never' to win — a passed 'fallback' handed every skipped file to yamlls instead.
    default_format_opts = {
      lsp_format = 'fallback',
    },

    format_on_save = function(bufnr)
      if vim.g.conform_format_on_save == false then
        return false
      end

      local bufname = vim.api.nvim_buf_get_name(bufnr)
      local filetype = vim.bo[bufnr].filetype

      local disable_filetypes = { 'sql', 'text', 'markdown' }
      if vim.tbl_contains(disable_filetypes, filetype) or off_on_save[filetype] then
        return false
      end

      -- files a role ships verbatim (Grafana dashboards, alert rules) and vendored code
      -- stay as their upstream wrote them: jsonls re-indented a 5k-line dashboard, yamlfmt
      -- turned a PromQL block into a quoted string
      if bufname:match '/roles/.*/files/' or bufname:match '/vendor/' then
        return false
      end

      local max_filesize = 100 * 1024
      local ok, stats = pcall(vim.uv.fs_stat, bufname)
      if ok and stats and stats.size > max_filesize then
        return false
      end

      return {
        timeout_ms = 3000,
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

      -- NOTE: a skipped file returns lsp_format = 'never', not an empty list — with no
      -- formatters the fallback handed it to yamlls, which re-indented a CRD by 1400 lines.
      -- NOTE: helm templates are left alone — yamlfmt breaks Go templating.
      yaml = function(bufnr)
        local skip = { lsp_format = 'never' }
        local name = vim.api.nvim_buf_get_name(bufnr)
        if vim.bo[bufnr].filetype == 'helm' or name:match '/templates/' then
          return skip
        end
        -- GitLab CI (the files yamlls maps to its schema): yamlfmt joins every multi-line
        -- plain scalar, and a wrapped script: command became one line of up to 834 chars
        if name:match '%.gitlab%-ci%.ya?ml$' or name:match '/%.gitlab/ci/' or name:match '/ci%-cd/' or name:match '/gitlab%-templates/' then
          return skip
        end
        -- NOTE: encrypted files are never formatted. yamlfmt folded an ansible-vault file
        -- ($ANSIBLE_VAULT header + hex lines) into a single scalar, which no longer
        -- decrypts, and re-indented the sops: metadata of every *.sops.yaml. Only sops and
        -- ansible-vault may write these.
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        if (lines[1] or ''):match '^%$ANSIBLE_VAULT' then
          return skip
        end
        for _, line in ipairs(lines) do
          if line:match '^sops:' then
            return skip
          end
          -- unquoted Jinja parses as a flow map: yamlfmt turned `foo: {{ bar }}` into
          -- `foo: {? {bar: ''} : ''}`; left alone, yamllint and ansible-lint point at it
          if line:match '^%s*[%w_-]+:%s*{%s*{' or line:match '^%s*%- {%s*{' then
            return skip
          end
          -- a CRD is upstream's file; re-indenting it is a 12k-line diff
          if line:match '^kind:%s*CustomResourceDefinition' then
            return skip
          end
        end
        return { 'yamlfmt' }
      end,

      bash = { 'shfmt' },
      zsh = { 'shfmt' },
      sh = { 'shfmt' },

      -- NOTE: plain HCL is not formatted. The only formatter at hand is terraform fmt,
      -- which on Nomad jobs unwrapped "${...}" interpolations and failed on templated job
      -- names; terraform-ls no longer attaches to hcl, so there is no LSP fallback either.
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

      -- NOTE: no -i here: conform appends -i <shiftwidth> whenever expandtab is set and
      -- the last flag wins, so the file's own indent (vim-sleuth) decides.
      shfmt = {
        prepend_args = {
          '-bn', -- binary operators at the start of a line
          '-ci', -- indent case branches
          '-sr', -- redirections after the command
        },
      },
    },
  },
}
