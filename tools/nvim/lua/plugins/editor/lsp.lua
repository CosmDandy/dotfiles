-- [[ LSP Config ]]
--
-- LSP Plugins
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

  -- mason-lspconfig - нужен для автонастройки LSP серверов
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
    event = 'BufReadPre',
    dependencies = {
      {
        'j-hui/fidget.nvim',
        opts = {
          notification = {
            window = {
              winblend = 0,
            },
          },
        },
      },
      'williamboman/mason.nvim',
      'williamboman/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',
      'hrsh7th/cmp-nvim-lsp',
    },
    config = function()
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('lsp-attach', { clear = true }),
        callback = function(event)
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          map('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')
          map('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
          map('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
          map('<leader>D', require('telescope.builtin').lsp_type_definitions, 'Type [D]efinition')

          map('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
          map('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

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

          if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
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

          if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
            map('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, '[T]oggle Inlay [H]ints')
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

      local capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities = vim.tbl_deep_extend('force', capabilities, require('cmp_nvim_lsp').default_capabilities())

      capabilities.textDocument.completion.completionItem.snippetSupport = true
      capabilities.textDocument.completion.completionItem.resolveSupport = {
        properties = { 'documentation', 'detail', 'additionalTextEdits' },
      }

      local servers = {
        pyright = {
          settings = {
            python = {
              analysis = {
                typeCheckingMode = 'basic',
                autoImportCompletions = true,
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                diagnosticMode = 'openFilesOnly', -- Для больших проектов
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
          root_dir = function(fname)
            local util = require 'lspconfig.util'
            return util.root_pattern('pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', '.git')(fname)
          end,
        },

        -- Lua LSP для конфигурации Neovim
        lua_ls = {
          settings = {
            Lua = {
              completion = {
                callSnippet = 'Replace',
              },
              diagnostics = {
                disable = { 'missing-fields' },
                globals = { 'vim' }, -- Добавляем vim как глобальную переменную
              },
              workspace = {
                checkThirdParty = false, -- Не спрашивать о сторонних библиотеках
              },
            },
          },
        },

        -- JSON LSP для конфигурационных файлов (package.json, docker-compose.yml schemas)
        jsonls = {
          settings = {
            json = {
              schemas = require('schemastore').json.schemas(),
              validate = { enable = true },
              -- Форматирование JSON файлов
              format = {
                enable = true,
                keepLines = false,
              },
            },
          },
        },

        -- YAML LSP для Docker Compose, Kubernetes, CI/CD файлов
        yamlls = {
          settings = {
            yaml = {
              schemaStore = {
                enable = true,
                url = 'https://www.schemastore.org/api/json/catalog.json',
              },
              schemas = {
                ['https://json.schemastore.org/github-workflow.json'] = '/.github/workflows/*.{yml,yaml}',
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
          filetypes = { 'yaml', 'yaml.docker-compose', 'yaml.gitlab', 'yaml.ansible' },
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
        },

        bashls = {
          filetypes = { 'sh', 'bash', 'zsh' },
          settings = {
            bashIde = {
              -- Включаем глобальные переменные окружения
              globPattern = '**/*@(.sh|.inc|.bash|.command)',
            },
          },
        },

        -- Docker LSP для работы с Dockerfile
        dockerls = {
          settings = {
            docker = {
              languageserver = {
                formatter = {
                  ignoreMultilineInstructions = true,
                },
              },
            },
          },
        },

        -- HTML/CSS для веб части проектов
        html = {
          configurationSection = { 'html', 'css', 'javascript' },
          embeddedLanguages = {
            css = true,
            javascript = true,
          },
          provideFormatter = true,
        },

        cssls = {
          settings = {
            css = {
              validate = true,
              lint = {
                unknownAtRules = 'ignore', -- Игнорируем неизвестные CSS правила
              },
            },
            scss = {
              validate = true,
            },
            less = {
              validate = true,
            },
          },
        },

        -- TypeScript для современных веб проектов
        ts_ls = {
          settings = {
            typescript = {
              inlayHints = {
                includeInlayParameterNameHints = 'all',
                includeInlayParameterNameHintsWhenArgumentMatchesName = false,
                includeInlayFunctionParameterTypeHints = true,
                includeInlayVariableTypeHints = true,
                includeInlayPropertyDeclarationTypeHints = true,
                includeInlayFunctionLikeReturnTypeHints = true,
                includeInlayEnumMemberValueHints = true,
              },
            },
            javascript = {
              inlayHints = {
                includeInlayParameterNameHints = 'all',
                includeInlayParameterNameHintsWhenArgumentMatchesName = false,
                includeInlayFunctionParameterTypeHints = true,
                includeInlayVariableTypeHints = true,
                includeInlayPropertyDeclarationTypeHints = true,
                includeInlayFunctionLikeReturnTypeHints = true,
                includeInlayEnumMemberValueHints = true,
              },
            },
          },
        },

        -- В lsp.lua, добавить в servers:
        terraformls = {
          filetypes = { 'terraform', 'hcl', 'tf' },
          settings = {
            terraform = {
              experimentalFeatures = {
                validateOnSave = true,
              },
            },
          },
        },

        -- Jinja2 LSP для Ansible шаблонов (.j2 файлы)
        jinja_lsp = {},

        -- Docker Compose LSP
        docker_compose_language_service = {},

        ansiblels = {
          settings = {
            ansible = {
              ansible = {
                path = 'ansible',
              },
              executionEnvironment = {
                enabled = false,
              },
              python = {
                interpreterPath = 'python3',
              },
              validation = {
                enabled = true,
                lint = {
                  enabled = true,
                  path = 'ansible-lint',
                },
              },
            },
          },
          filetypes = { 'yaml.ansible' },
        },
      }

      -- Список инструментов для автоматической установки через Mason
      local ensure_installed = vim.tbl_keys(servers or {})
      vim.list_extend(ensure_installed, {
        -- LSP серверы
        'pyright', -- Python LSP
        'lua-language-server', -- Lua LSP
        'json-lsp', -- JSON LSP
        'yaml-language-server', -- YAML LSP
        'bash-language-server', -- Bash LSP
        'dockerfile-language-server', -- Docker LSP
        'docker-compose-language-service', -- Docker Compose LSP
        'html-lsp', -- HTML LSP
        'css-lsp', -- CSS LSP
        'typescript-language-server', -- TypeScript/JavaScript LSP

        -- DAP для отладки
        'debugpy', -- Python debugger

        -- Linters для дополнительной проверки кода
        'ruff', -- Python linter (быстрый, современный)
        'mypy', -- Python type checker
        'luacheck', -- Lua linter
        'eslint_d', -- JavaScript/TypeScript linter
        'markuplint', -- HTML linter
        'stylelint', -- CSS linter
        'hadolint', -- Dockerfile linter
        'yamllint', -- YAML linter
        'shellcheck', -- Shell script linter

        -- Formatters для автоформатирования
        'black', -- Python formatter (стандарт PEP 8)
        'stylua', -- Lua formatter
        'prettierd', -- JavaScript/TypeScript/HTML/CSS formatter
        'yamlfmt', -- YAML formatter
        'xmlformatter', -- XML formatter
        'beautysh', -- Bash formatter
        'shfmt', -- Shell script formatter

        'terraform-ls',
        'tflint',

        'ansible-language-server',
        'ansible-lint',
        'jinja-lsp',
      })

      -- Автоматическая установка инструментов
      require('mason-tool-installer').setup {
        ensure_installed = ensure_installed,
        auto_update = false, -- Отключаем автообновление для быстрого запуска
        run_on_start = true, -- Включаем автоматическую установку при первом запуске
      }

      -- Настройка серверов через mason-lspconfig
      require('mason-lspconfig').setup {
        handlers = {
          function(server_name)
            local server = servers[server_name] or {}
            server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
            require('lspconfig')[server_name].setup(server)
          end,
        },
      }

      -- Дополнительная настройка schemastore для JSON/YAML
      local ok, schemastore = pcall(require, 'schemastore')
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
