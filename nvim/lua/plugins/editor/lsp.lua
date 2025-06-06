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
  {
    'neovim/nvim-lspconfig',
    event = 'BufReadPre',
    dependencies = {
      {
        'j-hui/fidget.nvim',
        opts = {
          -- Настраиваем уведомления LSP для лучшего UX
          notification = {
            window = {
              winblend = 0, -- Убираем прозрачность для четкости
            },
          },
        },
      },
      {
        'williamboman/mason.nvim',
        opts = {
          -- Настройки Mason для автоматической установки инструментов
          ui = {
            border = 'rounded',
            width = 0.8,
            height = 0.8,
          },
        },
      },
      'williamboman/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',
      'hrsh7th/cmp-nvim-lsp',
    },
    config = function()
      -- Настройка хоткеев при подключении LSP к буферу
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('python-devops-lsp-attach', { clear = true }),
        callback = function(event)
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          -- Основные навигационные хоткеи - оптимизированы для частого использования
          map('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')
          map('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
          map('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
          map('<leader>D', require('telescope.builtin').lsp_type_definitions, 'Type [D]efinition')

          -- Символы и навигация по проекту - критично для больших Python проектов
          map('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
          map('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

          -- Рефакторинг и действия с кодом
          map('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
          map('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction', { 'n', 'x' })
          map('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

          -- Дополнительные хоткеи для Python разработки
          map('<leader>li', '<cmd>LspInfo<CR>', '[L]SP [I]nfo')
          map('<leader>lr', '<cmd>LspRestart<CR>', '[L]SP [R]estart')

          local client = vim.lsp.get_client_by_id(event.data.client_id)

          -- Подсветка символов под курсором - помогает в навигации по коду
          if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
            local highlight_augroup = vim.api.nvim_create_augroup('python-devops-lsp-highlight', { clear = false })
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
              group = vim.api.nvim_create_augroup('python-devops-lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'python-devops-lsp-highlight', buffer = event2.buf }
              end,
            })
          end

          -- Inlay hints для Python - показывают типы переменных прямо в коде
          if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
            map('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, '[T]oggle Inlay [H]ints')
          end
        end,
      })

      -- Настройка иконок диагностики для лучшего визуального восприятия
      if vim.g.have_nerd_font then
        local signs = { ERROR = '', WARN = '', INFO = '', HINT = '󰌵' }
        local diagnostic_signs = {}
        for type, icon in pairs(signs) do
          diagnostic_signs[vim.diagnostic.severity[type]] = icon
        end
        vim.diagnostic.config {
          signs = { text = diagnostic_signs },
          -- Настройки отображения диагностики для Python разработки
          virtual_text = {
            prefix = '●', -- Символ перед текстом ошибки
            source = 'if_many', -- Показывать источник если несколько LSP активны
          },
          float = {
            border = 'rounded',
            source = 'always',      -- Всегда показывать источник в всплывающих окнах
          },
          severity_sort = true,     -- Сортировать по важности
          update_in_insert = false, -- Не отвлекать во время набора текста
        }
      end

      -- Получаем capabilities для автодополнений
      local capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities = vim.tbl_deep_extend('force', capabilities, require('cmp_nvim_lsp').default_capabilities())

      -- Оптимизируем capabilities для работы с большими Python проектами
      capabilities.textDocument.completion.completionItem.snippetSupport = true
      capabilities.textDocument.completion.completionItem.resolveSupport = {
        properties = { 'documentation', 'detail', 'additionalTextEdits' },
      }

      -- Конфигурация серверов с детальными настройками для каждого языка
      local servers = {
        -- Python LSP - самый важный для вашей работы
        pyright = {
          settings = {
            python = {
              analysis = {
                -- Уровень анализа - strict для максимальной проверки типов
                typeCheckingMode = 'strict',
                -- Автоимпорт - критично для Python разработки
                autoImportCompletions = true,
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                -- Диагностика специфично для Python проектов
                diagnosticMode = 'workspace', -- Анализ всего workspace, не только открытых файлов
                -- Включаем дополнительные проверки
                reportMissingImports = true,
                reportMissingTypeStubs = false, -- Отключаем для сторонних библиотек
                reportGeneralTypeIssues = true,
                reportOptionalMemberAccess = true,
                reportOptionalSubscript = true,
                reportPrivateImportUsage = false, -- Иногда нужно для тестов
              },
              -- Пути для поиска модулей
              pythonPath = './venv/bin/python', -- Автоматически ищет виртуальное окружение
            },
          },
          -- Дополнительные настройки для pyright
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
                enable = false, -- Отключаем встроенное хранилище схем
                url = '',
              },
              schemas = require('schemastore').yaml.schemas {
                -- Добавляем популярные схемы для DevOps
                select = {
                  'docker-compose.yml',
                  'GitHub Workflow',
                  'gitlab-ci',
                  'docker-compose.yml',
                },
              },
              -- Настройки валидации YAML
              validate = true,
              completion = true,
              hover = true,
              -- Форматирование YAML с правильными отступами
              format = {
                enable = true,
                singleQuote = false,
                bracketSpacing = true,
              },
            },
          },
        },

        -- Bash LSP для shell скриптов и DevOps автоматизации
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
      }

      -- Список инструментов для автоматической установки через Mason
      local ensure_installed = vim.tbl_keys(servers or {})
      vim.list_extend(ensure_installed, {
        -- LSP серверы
        'pyright',                         -- Python LSP
        'lua-language-server',             -- Lua LSP
        'json-lsp',                        -- JSON LSP
        'yaml-language-server',            -- YAML LSP
        'bash-language-server',            -- Bash LSP
        'dockerfile-language-server',      -- Docker LSP
        'docker-compose-language-service', -- Docker Compose LSP
        'html-lsp',                        -- HTML LSP
        'css-lsp',                         -- CSS LSP
        'typescript-language-server',      -- TypeScript/JavaScript LSP

        -- DAP для отладки
        'debugpy', -- Python debugger

        -- Linters для дополнительной проверки кода
        'ruff',       -- Python linter (быстрый, современный)
        'mypy',       -- Python type checker
        'pylint',     -- Python code analysis
        'luacheck',   -- Lua linter
        'eslint_d',   -- JavaScript/TypeScript linter
        'markuplint', -- HTML linter
        'stylelint',  -- CSS linter
        'hadolint',   -- Dockerfile linter
        'yamllint',   -- YAML linter
        'shellcheck', -- Shell script linter

        -- Formatters для автоформатирования
        'black',        -- Python formatter (стандарт PEP 8)
        'isort',        -- Python import sorter
        'stylua',       -- Lua formatter
        'prettierd',    -- JavaScript/TypeScript/HTML/CSS formatter
        'yamlfmt',      -- YAML formatter
        'xmlformatter', -- XML formatter
        'beautysh',     -- Bash formatter
        'shfmt',        -- Shell script formatter
      })

      -- Автоматическая установка инструментов
      require('mason-tool-installer').setup {
        ensure_installed = ensure_installed,
        auto_update = true,  -- Автообновление инструментов
        run_on_start = true, -- Проверка при запуске
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
