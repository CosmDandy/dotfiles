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

  -- mason-lspconfig - в 2.0 сам вызывает vim.lsp.enable для установленных серверов.
  -- lazy=false не нужен: setup{} вызывается из config() nvim-lspconfig, который
  -- и так тянет этот плагин через свои dependencies (см. ниже).
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
      -- грузится с lspconfig, чтобы require в lsp/*.lua работал; version=false — последний тег устаревший
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

          -- Символы документа и проекта живут в пространстве [s]earch:
          -- <leader>so и <leader>sS (snacks-picker.lua)

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

          -- подсветку вхождений символа (document_highlight) + прыжки ]]/[[ ведёт snacks.words

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
        -- значки в гаттере выключены (не нравятся в колонке номеров строк)
        signs = false,
        -- инлайн-текста/маркеров нет: только подчёркивание (цвет по важности от темы)
        -- + детали снизу через virtual_lines под курсором (см. автокоманду ниже)
        virtual_text = false,
        float = {
          border = 'rounded',
          -- true, а не 'always': 'always' — значение до-0.10 API, тип теперь
          -- boolean|'if_many'. Работало по случайности, как непустая строка.
          source = true,
          header = '',
          focusable = false,
        },
        -- по умолчанию показываем все диагностики постоянно (vl_all ниже); toggle <leader>tD
        virtual_lines = true,
        severity_sort = true,
        -- update_in_insert СОЗНАТЕЛЬНО не включён (дефолт false). :h vim.diagnostic.Opts
        -- называет его дорогим, и ни kickstart, ни LazyVim его не ставят. Здесь цена
        -- была бы тройной: с virtual_lines выше на каждое нажатие пересобирался бы
        -- многострочный виртуальный блок, а рядом ещё nvim-lint на TextChanged
        -- (lint.lua). Мерцание в insert-режиме, ради которого его когда-то включили,
        -- как раз им и вызывается, а не лечится.
      }

      -- virtual_lines под курсором появляются через 500мс покоя (не дёргают вьюпорт при скролле).
      -- vl_auto — авто-показ под курсором (toggle <leader>td); vl_all — «развернуть ВСЕ» (<leader>tD)
      local vl_auto = true
      local vl_all = true
      local vl_shown = false
      local vl_timer = assert((vim.uv or vim.loop).new_timer())
      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        group = vim.api.nvim_create_augroup('diag-vlines-delay', { clear = true }),
        callback = function()
          if vl_all or not vl_auto then
            return -- режим «все» или авто-показ выключен — курсор не трогает virtual_lines
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

      -- <leader>tD — развернуть/свернуть ВСЕ диагностики (virtual_lines под каждой строкой)
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

      -- <leader>td — вкл/выкл авто-показ диагностики под курсором (underline остаётся)
      vim.keymap.set('n', '<leader>td', function()
        vl_auto = not vl_auto
        if not vl_auto then
          vl_timer:stop()
          vl_shown = false
          if not vl_all then
            vim.diagnostic.config { virtual_lines = false }
          end
        end
        -- если включили обратно — покажется на следующем покое курсора
      end, { desc = '[T]oggle auto under-cursor [d]iagnostics' })

      -- Дельты серверов вынесены в lua/../lsp/<name>.lua (нативная конвенция 0.11+):
      -- nvim авто-загружает их при vim.lsp.enable.
      -- docker_compose_language_service / jsonnet_ls — без дельт (shipped-конфиги полные).
      --
      -- Capabilities (completion/snippets) на vim.lsp.config('*', ...) отдельно ЗДЕСЬ
      -- не вешаем: blink.cmp делает это сам в своём plugin/blink-cmp.lua при загрузке
      -- (см. lua/plugins/editor/blink-cmp.lua) — дублирующий require('blink.cmp') тут
      -- был бы лишней ручной копией того же вызова.

      -- Mason package names (НЕ lspconfig names) — для установки инструментов
      local ensure_installed = {
        -- LSP серверы
        'basedpyright',
        'lua-language-server',
        'json-lsp',
        'yaml-language-server',
        'bash-language-server',
        'dockerfile-language-server',
        'docker-compose-language-service',
        'terraform-ls',
        'ansible-language-server',
        'helm-ls',
        'jsonnet-language-server',
        -- marksman — LSP для Markdown: переходы по ссылкам между документами и
        -- по заголовкам. В репозитории 24 .md, docs/ читается постоянно.
        'marksman',
        -- LSP для Nix (nil) здесь СОЗНАТЕЛЬНО нет: mason ставит его через cargo,
        -- которого в системе нет, и установка молча падает с ENOENT. Он приходит
        -- из nixpkgs — см. `nil` и `nixfmt` в environment.systemPackages
        -- (platform/nix/darwin-configuration.nix). nvim-lspconfig подхватывает
        -- бинарь `nil` из PATH сам, дельта-конфига ему не нужно.
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
        -- false, потому что это дубль: MasonToolsInstallSync уже вызывается при каждой
        -- активации home-manager (platform/nix/home/hooks.nix:122). С true тот же обход
        -- 25 пакетов повторялся при первом открытии файла в каждом запуске nvim —
        -- lspconfig грузится на BufReadPre, а его config и делает этот setup.
        -- Доустановить руками: :MasonToolsInstall
        run_on_start = false,
      }

      -- mason-lspconfig 2.0: automatic_enable как whitelist — только реальные LSP-серверы
      -- (иначе formatters/linters stylua/ruff/tflint цепляются как LSP; они и так
      --  работают через conform/nvim-lint)
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
    end,
  },
}
