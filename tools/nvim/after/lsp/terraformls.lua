return {
  -- NOTE: no hcl. terraform-ls has no features for plain HCL ("no feature found for
  -- language hcl" on every request) except formatting, which is terraform fmt — on Nomad
  -- jobs it unwrapped "${...}" interpolations and failed on templated job names.
  filetypes = { 'terraform', 'terraform-vars' },
  -- terraform-ls runs terraform with the server's environment, and `providers schema`
  -- loads the backend: the http backend's credentials come from the repo's .envrc
  -- (TF_HTTP_* built from GITLAB_TOKEN). nvim started outside that directory had none —
  -- 401, and no schemas for community providers in live dirs. The server gets the
  -- environment of the nearest .envrc, whatever the backend.
  -- NOTE: `direnv export json`, not `direnv exec`: exec exits 1 on a blocked .envrc
  -- (taking the server down) and prints "direnv: loading" to the server's stderr, which
  -- nvim logs as an error — DIRENV_LOG_FORMAT='' does not silence it in direnv 2.37.
  -- A blocked .envrc exports nothing, and nvim's own environment is used.
  cmd = function(dispatchers, config)
    local env, unset = nil, {}
    if config.root_dir and vim.fn.executable 'direnv' == 1 then
      -- NOTE: 5 s cap — this runs on the UI thread, and a slow .envrc (an uncached
      -- `use flake`) would freeze nvim; past it the server keeps nvim's environment
      local out = vim.system({ 'direnv', 'export', 'json' }, { cwd = config.root_dir, text = true }):wait(5000)
      local ok, vars = pcall(vim.json.decode, out.code == 0 and out.stdout ~= '' and out.stdout or 'null')
      if ok and type(vars) == 'table' then
        env = {}
        for k, v in pairs(vars) do
          if type(v) == 'string' then
            env[k] = v
          else
            -- null: unset — left over from another directory's .envrc nvim was started
            -- under; vim.system can only add variables, so env -u drops them
            vim.list_extend(unset, { '-u', k })
          end
        end
      end
    end
    -- without -log-file terraform-ls traces to stderr, which nvim keeps in lsp.log at
    -- ERROR level: 11 MB from one repo
    local cmd = { 'terraform-ls', 'serve', '-log-file=/dev/null' }
    if #unset > 0 then
      cmd = vim.list_extend(vim.list_extend({ 'env' }, unset), cmd)
    end
    return vim.lsp.rpc.start(cmd, dispatchers, { cwd = config.root_dir, env = env })
  end,
  -- NOTE: init_options, not settings: terraform-ls reads these from initializationOptions
  -- only and answers workspace/didChangeConfiguration with "method not found", so
  -- validate-on-save never ran.
  init_options = {
    experimentalFeatures = {
      validateOnSave = true,
    },
    -- ansible-lint installs galaxy collections into <project>/.ansible: 1809 of the 2046
    -- directories terraform-ls walked in one repo
    indexing = {
      ignoreDirectoryNames = { '.ansible' },
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
            -- hears about .terraform; the hand-made one, as `:lsp restart` left it stopped
            require 'config.lsp_restart'(vim.lsp.get_clients { name = 'terraformls' })
            vim.notify('terraform init: providers in place, terraform-ls restarted', vim.log.levels.INFO)
          else
            vim.notify('terraform init failed:\n' .. (out.stderr or ''), vim.log.levels.ERROR)
          end
        end)
      end)
    end, { desc = 'Fetch providers for completion (no backend)' })
  end,
}
