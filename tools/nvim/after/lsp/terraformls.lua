return {
  filetypes = { 'terraform', 'terraform-vars', 'hcl' },
  settings = {
    terraform = {
      experimentalFeatures = {
        validateOnSave = true,
      },
    },
  },

  -- Resource attribute completion needs the provider schemas, which terraform-ls reads
  -- from .terraform after an init; a fresh clone has none and offers only the
  -- meta-arguments (count, for_each). :TerraformInit fetches the providers without the
  -- backend (no state, no credentials) and restarts terraform-ls to load the schemas.
  -- NOTE: this replaces lspconfig's on_attach, which only enabled codelens — lsp.lua's
  -- LspAttach already does that for every server that supports it.
  on_attach = function(_, bufnr)
    vim.api.nvim_buf_create_user_command(bufnr, 'TerraformInit', function()
      local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
      vim.notify('terraform init -backend=false in ' .. dir, vim.log.levels.INFO)
      -- NOTE: no -lockfile=readonly. A lock committed from another platform lacks this
      -- platform's h1: checksum; readonly left it out, and `terraform providers schema`
      -- then refused the installed plugin, so terraform-ls had no schemas (verified).
      -- A plain init adds that one line to the lock — worth committing.
      local cmd = { 'terraform', 'init', '-backend=false', '-input=false', '-no-color' }
      vim.system(cmd, { cwd = dir, text = true }, function(out)
        vim.schedule(function()
          if out.code == 0 then
            -- NOTE: a restart, because on Linux nvim 0.12 advertises no file watching
            -- (protocol.lua, Darwin/Windows only) and terraform-ls in a devcontainer never
            -- hears about .terraform. A hand-made one: `:lsp restart` stopped the client
            -- and started none (verified) — lsp.start reused the stopped client, which
            -- stays listed, so reuse_client here skips stopped ones.
            for _, c in ipairs(vim.lsp.get_clients { name = 'terraformls' }) do
              local bufs, config = vim.tbl_keys(c.attached_buffers), c.config
              c:stop()
              vim.wait(5000, function()
                return c:is_stopped()
              end, 50)
              for _, b in ipairs(bufs) do
                -- NOTE: the root is found again: opened before the init, the module had
                -- no .terraform yet and the old client's root is the repo (.git)
                local root = vim.fs.root(b, { '.terraform', '.git' }) or config.root_dir
                vim.lsp.start(vim.tbl_extend('force', config, { root_dir = root }), {
                  bufnr = b,
                  reuse_client = function(client, cfg)
                    return client.name == cfg.name and client.root_dir == cfg.root_dir and not client:is_stopped()
                  end,
                })
              end
            end
            vim.notify('terraform init: providers in place, terraform-ls restarted', vim.log.levels.INFO)
          else
            vim.notify('terraform init failed:\n' .. (out.stderr or ''), vim.log.levels.ERROR)
          end
        end)
      end)
    end, { desc = 'Fetch providers for completion (no backend)' })
  end,
}
