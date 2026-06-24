-- [[ LSP Config ]] — нативный vim.lsp.config (nvim 0.11+), mason-lspconfig 2.0 auto-enable
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

  -- Mason UI - загружается только по команде :Mason
  {
    'williamboman/mason.nvim',
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

  -- mason-lspconfig - в 2.0 сам вызывает vim.lsp.enable для установленных серверов
  {
    'williamboman/mason-lspconfig.nvim',
    lazy = false,
    priority = 51,
  },

  -- mason-tool-installer - автоустановка инструментов
  {
    'WhoIsSethDaniel/mason-tool-installer.nvim',
    event = 'VeryLazy',
  },

  {
    'neovim/nvim-lspconfig',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = {
      'williamboman/mason.nvim',
      'williamboman/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',
      'saghen/blink.cmp',
    },
    config = function()
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('lsp-attach', { clear = true }),
        callback = function(event)
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          map('gd', function() Snacks.picker.lsp_definitions() end, '[G]oto [D]efinition')
          map('gr', function() Snacks.picker.lsp_references() end, '[G]oto [R]eferences')
          map('gI', function() Snacks.picker.lsp_implementations() end, '[G]oto [I]mplementation')
          map('<leader>D', function() Snacks.picker.lsp_type_definitions() end, 'Type [D]efinition')

          map('<leader>ds', function() Snacks.picker.lsp_symbols() end, '[D]ocument [S]ymbols')
          map('<leader>ws', function() Snacks.picker.lsp_workspace_symbols() end, '[W]orkspace [S]ymbols')

          map('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
          map('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction', { 'n', 'x' })
          map('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

          map('K', vim.lsp.buf.hover, 'Hover Documentation')
          map('<leader>k', vim.lsp.buf.signature_help, 'Signature Help')

          map(']d', vim.diagnostic.goto_next, 'Next [D]iagnostic')
          map('[d', vim.diagnostic.goto_prev, 'Previous [D]iagnostic')
          map('<leader>e', vim.diagnostic.open_float, 'Show [E]rror')
          map('<leader>dq', vim.diagnostic.setloclist, '[D]iagnostics [Q]uickfix')

          map('<leader>li', '<cmd>LspInfo<CR>', '[L]SP [I]nfo')
          map('<leader>lr', '<cmd>LspRestart<CR>', '[L]SP [R]estart')

          local client = vim.lsp.get_client_by_id(event.data.client_id)

          if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
            local highlight_augroup = vim.api.nvim_create_augroup('lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })

            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'lsp-highlight', buffer = event2.buf }
              end,
            })
          end

          if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
            map('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, '[T]oggle Inlay [H]ints')
          end

          -- CodeLens (счётчики ссылок lua_ls/terraform) — декларативно, nvim сам обновляет
          if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_codeLens) then
            vim.lsp.codelens.enable(true, { bufnr = event.buf })
          end
        end,
      })

      vim.diagnostic.config {
        signs = false,
        virtual_text = {
          prefix = '●',
          source = 'if_many',
        },
        float = {
          border = 'rounded',
          source = 'always',
          header = '',
          focusable = false,
        },
        severity_sort = true,
        update_in_insert = false,
      }

      -- Capabilities (blink.cmp) — глобально для всех серверов
      vim.lsp.config('*', {
        capabilities = require('blink.cmp').get_lsp_capabilities(),
      })

      -- Дельты настроек серверов (mason-lspconfig 2.0 сам их vim.lsp.enable)
      vim.lsp.config('pyright', {
        settings = {
          python = {
            analysis = {
              typeCheckingMode = 'basic',
              autoImportCompletions = true,
              autoSearchPaths = true,
              useLibraryCodeForTypes = true,
              diagnosticMode = 'openFilesOnly',
              reportMissingImports = true,
              reportMissingTypeStubs = false,
              reportGeneralTypeIssues = true,
              reportOptionalMemberAccess = true,
              reportOptionalSubscript = true,
              reportPrivateImportUsage = false,
            },
            pythonPath = './venv/bin/python',
          },
        },
      })

      vim.lsp.config('lua_ls', {
        settings = {
          Lua = {
            completion = { callSnippet = 'Replace' },
            diagnostics = {
              disable = { 'missing-fields' },
              globals = { 'vim' },
            },
            workspace = { checkThirdParty = false },
          },
        },
      })

      vim.lsp.config('jsonls', {
        settings = {
          json = {
            schemas = require('schemastore').json.schemas(),
            validate = { enable = true },
            format = { enable = true, keepLines = false },
          },
        },
      })

      vim.lsp.config('yamlls', {
        filetypes = { 'yaml', 'yaml.docker-compose', 'yaml.gitlab', 'yaml.ansible' },
        settings = {
          yaml = {
            schemaStore = {
              enable = true,
              url = 'https://www.schemastore.org/api/json/catalog.json',
            },
            schemas = {
              ['https://json.schemastore.org/github-workflow.json'] = { '/.github/workflows/*.{yml,yaml}', '/.github/workflows/*.tpl' },
              ['https://gitlab.com/gitlab-org/gitlab/-/raw/master/app/assets/javascripts/editor/schema/ci.json'] = {
                '**/.gitlab-ci.yml',
                '**/.gitlab-ci.yaml',
              },
              ['https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json'] = {
                '**/docker-compose*.yml',
                '**/docker-compose*.yaml',
                '**/compose.yml',
                '**/compose.yaml',
              },
              ['https://raw.githubusercontent.com/ansible/ansible-lint/main/src/ansiblelint/schemas/ansible.json#/$defs/playbook'] = {
                '**/*playbook*.yml',
                '**/*playbook*.yaml',
              },
              kubernetes = {
                '**/*.k8s.yaml',
                '**/k8s/**/*.yaml',
                '**/kubernetes/**/*.yaml',
              },
            },
            validate = true,
            completion = true,
            hover = true,
            format = {
              enable = true,
              singleQuote = false,
              bracketSpacing = true,
            },
            customTags = {
              '!vault',
              '!encrypted/pkcs1-oaep',
              '!reference sequence',
            },
          },
        },
        capabilities = {
          textDocument = {
            completion = {
              completionItem = {
                documentationFormat = { 'markdown', 'plaintext' },
                snippetSupport = true,
              },
            },
          },
        },
      })

      vim.lsp.config('bashls', {
        filetypes = { 'sh', 'bash', 'zsh' },
        settings = {
          bashIde = {
            globPattern = '**/*@(.sh|.inc|.bash|.command)',
          },
        },
      })

      vim.lsp.config('dockerls', {
        settings = {
          docker = {
            languageserver = {
              formatter = {
                ignoreMultilineInstructions = true,
              },
            },
          },
        },
      })

      vim.lsp.config('terraformls', {
        filetypes = { 'terraform', 'hcl', 'tf' },
        settings = {
          terraform = {
            experimentalFeatures = {
              validateOnSave = true,
            },
          },
        },
      })

      vim.lsp.config('helm_ls', {
        filetypes = { 'helm' },
      })

      vim.lsp.config('ansiblels', {
        filetypes = { 'yaml.ansible' },
        settings = {
          ansible = {
            ansible = { path = 'ansible' },
            executionEnvironment = { enabled = false },
            python = { interpreterPath = 'python3' },
            validation = {
              enabled = true,
              lint = { enabled = true, path = 'ansible-lint' },
            },
          },
        },
      })

      -- jinja_lsp, docker_compose_language_service, jsonnet_ls — без дельт
      -- (shipped-конфиги полные, automatic_enable их включит сам)

      -- Mason package names (НЕ lspconfig names) — для установки инструментов
      local ensure_installed = {
        -- LSP серверы
        'pyright',
        'lua-language-server',
        'json-lsp',
        'yaml-language-server',
        'bash-language-server',
        'dockerfile-language-server',
        'docker-compose-language-service',
        'terraform-ls',
        'ansible-language-server',
        'helm-ls',
        'jinja-lsp',
        'jsonnet-language-server',
        -- DAP
        'debugpy',
        -- Linters
        'ruff',
        'mypy',
        'luacheck',
        'hadolint',
        'yamllint',
        'shellcheck',
        'tflint',
        'ansible-lint',
        -- Formatters
        'stylua',
        'yamlfmt',
        'shfmt',
      }

      require('mason-tool-installer').setup {
        ensure_installed = ensure_installed,
        auto_update = false,
        run_on_start = true,
      }

      -- mason-lspconfig 2.0: automatic_enable=true сам вызывает vim.lsp.enable
      -- для установленных серверов — handlers больше не нужны
      require('mason-lspconfig').setup {}

      local ok = pcall(require, 'schemastore')
      if not ok then
        vim.notify('schemastore not found. Install it for better JSON/YAML support', vim.log.levels.WARN)
      end
    end,
  },

  -- Дополнительный плагин для JSON/YAML схем
  {
    'b0o/schemastore.nvim',
    lazy = true,
    dependencies = {
      'neovim/nvim-lspconfig',
    },
  },
}
