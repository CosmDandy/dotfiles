-- LSP config on native vim.lsp.config (nvim 0.11+) with mason-lspconfig 2.0
-- auto-enable
return {
  {
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
      },
    },
  },

  {
    'mason-org/mason.nvim',
    cmd = 'Mason',
    keys = { { '<leader>cm', '<cmd>Mason<cr>', desc = 'Mason' } },
    opts = {
      ui = {
        border = 'rounded',
        width = 0.8,
        height = 0.8,
      },
    },
  },

  -- In 2.0 it calls vim.lsp.enable for installed servers itself. No lazy=false
  -- needed: setup{} is called from nvim-lspconfig's config(), which pulls this
  -- plugin in anyway.
  {
    'mason-org/mason-lspconfig.nvim',
  },

  {
    'neovim/nvim-lspconfig',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = {
      'mason-org/mason.nvim',
      'mason-org/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',
      'saghen/blink.cmp',
      -- loaded with lspconfig so require works in lsp/*.lua; version=false
      -- because the latest tag is stale
      { 'b0o/schemastore.nvim', version = false },
    },
    config = function()
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('lsp-attach', { clear = true }),
        callback = function(event)
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          map('gd', function()
            Snacks.picker.lsp_definitions()
          end, '[G]oto [D]efinition')
          map('gr', function()
            Snacks.picker.lsp_references()
          end, '[G]oto [R]eferences')
          map('gI', function()
            Snacks.picker.lsp_implementations()
          end, '[G]oto [I]mplementation')
          map('<leader>D', function()
            Snacks.picker.lsp_type_definitions()
          end, 'Type [D]efinition')

          -- document and workspace symbols live in the [s]earch space:
          -- <leader>so / <leader>sS

          map('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
          map('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction', { 'n', 'x' })
          map('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

          map('K', function()
            vim.lsp.buf.hover { border = 'rounded', max_width = 80, max_height = 25 }
          end, 'Hover Documentation')
          map('<leader>k', vim.lsp.buf.signature_help, 'Signature Help')

          map(']d', function()
            vim.diagnostic.jump { count = 1 }
          end, 'Next [D]iagnostic')
          map('[d', function()
            vim.diagnostic.jump { count = -1 }
          end, 'Previous [D]iagnostic')

          map('<leader>lr', '<cmd>LspRestart<CR>', '[L]SP [R]estart')

          local client = vim.lsp.get_client_by_id(event.data.client_id)

          -- document_highlight and the ]]/[[ jumps are handled by snacks.words

          if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
            map('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, '[T]oggle Inlay [H]ints')
          end

          if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_codeLens) then
            vim.lsp.codelens.enable(true, { bufnr = event.buf })
          end
        end,
      })

      vim.diagnostic.config {
        signs = false,
        -- no inline text: underline only, with details below through
        -- virtual_lines
        virtual_text = false,
        float = {
          border = 'rounded',
          -- NOTE: true, not 'always' — that was the pre-0.10 API value and only
          -- worked by accident, as a non-empty string.
          source = true,
          header = '',
          focusable = false,
        },
        virtual_lines = true,
        severity_sort = true,
        -- NOTE: update_in_insert is deliberately left off. :h
        -- vim.diagnostic.Opts calls it expensive, and here the price would be
        -- triple: with virtual_lines above, every keystroke rebuilds a
        -- multi-line virtual block while nvim-lint also runs on TextChanged.
        -- The insert-mode flicker it was once enabled for is caused by it.
      }

      -- virtual_lines appear under the cursor after 500ms of rest, so scrolling
      -- does not jerk the viewport. vl_auto is the under-cursor display
      -- (<leader>td), vl_all is "expand everything" (<leader>tD).
      local vl_auto = true
      local vl_all = true
      local vl_shown = false
      local vl_timer = assert((vim.uv or vim.loop).new_timer())
      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        group = vim.api.nvim_create_augroup('diag-vlines-delay', { clear = true }),
        callback = function()
          if vl_all or not vl_auto then
            return
          end
          if vl_shown then
            vl_shown = false
            vim.diagnostic.config { virtual_lines = false }
          end
          vl_timer:stop()
          vl_timer:start(
            500,
            0,
            vim.schedule_wrap(function()
              vl_shown = true
              vim.diagnostic.config { virtual_lines = { current_line = true } }
            end)
          )
        end,
      })

      vim.keymap.set('n', '<leader>tD', function()
        vl_all = not vl_all
        vl_timer:stop()
        vl_shown = false
        if vl_all then
          vim.diagnostic.config { virtual_lines = true }
        else
          vim.diagnostic.config { virtual_lines = vl_auto and { current_line = true } or false }
        end
      end, { desc = '[T]oggle expand all [D]iagnostics' })

      vim.keymap.set('n', '<leader>td', function()
        vl_auto = not vl_auto
        if not vl_auto then
          vl_timer:stop()
          vl_shown = false
          if not vl_all then
            vim.diagnostic.config { virtual_lines = false }
          end
        end
      end, { desc = '[T]oggle auto under-cursor [d]iagnostics' })

      -- Per-server deltas live in lsp/<name>.lua (the native 0.11+ convention)
      -- and nvim loads them on vim.lsp.enable.
      -- NOTE: capabilities are NOT set here through vim.lsp.config('*', …) —
      -- blink.cmp does that itself in its own plugin/ directory, and a second
      -- call would be a hand copy of the same thing.

      -- Mason package names, NOT lspconfig names.
      local ensure_installed = {
        -- LSP servers
        'basedpyright',
        'lua-language-server',
        'json-lsp',
        'yaml-language-server',
        'bash-language-server',
        'dockerfile-language-server',
        'docker-compose-language-service',
        'marksman',
        -- NOTE: nil (the Nix LSP) is deliberately absent — mason installs it
        -- through cargo, which is not on the system, and the install fails
        -- silently with ENOENT. It comes from nixpkgs instead, and lspconfig
        -- picks the binary up from PATH. DAP
        'debugpy',
        -- Linters
        'ruff',
        'mypy',
        'luacheck',
        'hadolint',
        'yamllint',
        'shellcheck',
        -- Formatters
        'stylua',
        'yamlfmt',
        'shfmt',
      }

      -- IaC tooling is installed only where it is used. The container profile
      -- is written by platform/linux/install.sh and baked by the Dockerfile; on
      -- the mac the file does not exist and everything is installed.
      -- NOTE: measured in the :core image, these five took 275 MB of the 988 MB
      -- mason directory in a profile declared as "editor, shell, git".
      -- NOTE: jsonnet-language-server belongs here too — mason builds it with
      -- go, which only exists in the devops profile, so in core it failed with
      -- "Could not find executable go in PATH".
      local iac_tools = {
        'terraform-ls',
        'ansible-language-server',
        'helm-ls',
        'jsonnet-language-server',
        'tflint',
        'ansible-lint',
      }
      local profile_file = vim.fn.expand '~/.dotfiles-profile'
      local profile = ''
      if vim.fn.filereadable(profile_file) == 1 then
        profile = vim.trim(vim.fn.readfile(profile_file)[1] or '')
      end
      if profile ~= 'core' then
        vim.list_extend(ensure_installed, iac_tools)
      end

      require('mason-tool-installer').setup {
        ensure_installed = ensure_installed,
        auto_update = false,
        -- NOTE: false because it duplicates MasonToolsInstallSync, which every
        -- home-manager activation already runs. With true, the same walk over
        -- 25 packages repeated on the first file opened in every nvim run. To
        -- install by hand: :MasonToolsInstall
        run_on_start = false,
      }

      -- NOTE: automatic_enable is used as a whitelist — otherwise formatters
      -- and linters like stylua, ruff and tflint attach as LSP servers, while
      -- they already work through conform and nvim-lint.
      require('mason-lspconfig').setup {
        automatic_enable = {
          'basedpyright',
          'lua_ls',
          'jsonls',
          'yamlls',
          'bashls',
          'dockerls',
          'terraformls',
          'helm_ls',
          'ansiblels',
          'jsonnet_ls',
          'docker_compose_language_service',
        },
      }

      -- gopls comes from nixpkgs, not mason, so automatic_enable above never
      -- sees it — mason-lspconfig only enables what it installed itself. The
      -- executable check is for the core profile, which carries no Go tooling
      -- at all (platform/nix/home/default.nix): without it nvim would try to
      -- spawn a missing binary on every .go file.
      if vim.fn.executable 'gopls' == 1 then
        vim.lsp.enable 'gopls'
      end
    end,
  },
}
