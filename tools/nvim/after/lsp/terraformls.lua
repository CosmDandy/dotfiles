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
  -- backend (no state, no credentials), and terraform-ls picks the schemas up by itself.
  -- NOTE: -lockfile=readonly — a plain init added this platform's checksums to the
  -- committed .terraform.lock.hcl; readonly verifies against the recorded zh: hashes.
  -- NOTE: this replaces lspconfig's on_attach, which only enabled codelens — lsp.lua's
  -- LspAttach already does that for every server that supports it.
  on_attach = function(_, bufnr)
    vim.api.nvim_buf_create_user_command(bufnr, 'TerraformInit', function()
      local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
      vim.notify('terraform init -backend=false in ' .. dir, vim.log.levels.INFO)
      local cmd = { 'terraform', 'init', '-backend=false', '-input=false', '-no-color' }
      -- readonly only against an existing lock file: without one every provider is a new
      -- entry, and a readonly init refuses to run at all
      if vim.uv.fs_stat(dir .. '/.terraform.lock.hcl') then
        table.insert(cmd, '-lockfile=readonly')
      end
      vim.system(cmd, { cwd = dir, text = true }, function(out)
        vim.schedule(function()
          if out.code == 0 then
            -- NOTE: no automatic restart. On Linux nvim 0.12 advertises no file watching
            -- (protocol.lua, Darwin/Windows only), so terraform-ls in a devcontainer never
            -- hears about .terraform; and `:lsp restart terraformls` stopped the client
            -- without starting a new one (verified). A fresh session loads the schemas.
            vim.notify('terraform init: providers in place — reopen nvim for attribute completion', vim.log.levels.INFO)
          else
            vim.notify('terraform init failed:\n' .. (out.stderr or ''), vim.log.levels.ERROR)
          end
        end)
      end)
    end, { desc = 'Fetch providers for completion (no backend)' })
  end,
}
