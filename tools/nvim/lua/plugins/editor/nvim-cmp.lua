-- Autocompletion
--
-- For an understanding of why these mappings were
-- chosen, you will need to read `:help ins-completion`
--
-- No, but seriously. Please read `:help ins-completion`, it is really good!
return {
  'hrsh7th/nvim-cmp',
  event = 'InsertEnter',
  dependencies = {
    {
      'L3MON4D3/LuaSnip',
      event = 'InsertEnter',
      build = (function()
        return 'make install_jsregexp'
      end)(),
      dependencies = {
        {
          'rafamadriz/friendly-snippets',
          config = function()
            require('luasnip.loaders.from_vscode').lazy_load {
              include = {
                'python',
                'lua',
                'yaml',
                'json',
                'bash',
                'sh',
                'dockerfile',
                'terraform',
                'hcl',
                'markdown',
                'toml',
                'go',
              },
            }
          end,
        },
      },
    },
    'saadparwaiz1/cmp_luasnip',
    'hrsh7th/cmp-nvim-lsp',
    'hrsh7th/cmp-path',
    'hrsh7th/cmp-buffer',
    'hrsh7th/cmp-cmdline',
    'hrsh7th/cmp-nvim-lsp-signature-help',
    'lukas-reineke/cmp-under-comparator', -- Лучшая сортировка _ в конец
    -- 'windwp/nvim-ts-autotag',
    -- 'davidsierradz/cmp-conventionalcommits',
  },
  config = function()
    local cmp = require 'cmp'
    local luasnip = require 'luasnip'
    luasnip.config.setup {}

    cmp.setup {
      snippet = {
        expand = function(args)
          luasnip.lsp_expand(args.body)
        end,
      },
      completion = {
        completeopt = 'menu,menuone,noselect',
        keyword_pattern = [[\k\+]],
      },

      view = {
        entries = { name = 'custom', selection_order = 'near_cursor' },
        docs = {
          auto_open = true,
        },
      },

      mapping = cmp.mapping.preset.insert {
        -- Select the [n]ext item
        ['<C-n>'] = cmp.mapping.select_next_item(),
        -- Select the [p]revious item
        ['<C-p>'] = cmp.mapping.select_prev_item(),

        -- Scroll the documentation window [b]ack / [f]orward
        ['<C-b>'] = cmp.mapping.scroll_docs(-4),
        ['<C-f>'] = cmp.mapping.scroll_docs(4),

        -- Accept ([y]es) the completion.
        --  This will auto-import if your LSP supports it.
        --  This will expand snippets if the LSP sent a snippet.
        ['<Tab>'] = cmp.mapping.confirm { select = true },
        -- ['<C-y>'] = cmp.mapping.confirm { select = true },
        -- ['<CR>'] = cmp.mapping.confirm { select = true },
        -- ['<Tab>'] = cmp.mapping.select_next_item(),
        -- ['<S-Tab>'] = cmp.mapping.select_prev_item(),

        -- Manually trigger a completion from nvim-cmp.
        ['<C-Space>'] = cmp.mapping.complete {},

        -- <c-e> will move you to the right of each of the expansion locations.
        ['<C-e>'] = cmp.mapping(function()
          if luasnip.expand_or_locally_jumpable() then
            luasnip.expand_or_jump()
          end
        end, { 'i', 's' }),

        -- <c-y> is similar, except moving you backwards.
        ['<C-y>'] = cmp.mapping(function()
          if luasnip.locally_jumpable(-1) then
            luasnip.jump(-1)
          end
        end, { 'i', 's' }),

        -- Copilot accept
        ['<C-g>'] = cmp.mapping(function(fallback)
          vim.api.nvim_feedkeys(vim.fn['copilot#Accept'](vim.api.nvim_replace_termcodes('<Tab>', true, true, true)), 'n', true)
        end),
        -- For more advanced Luasnip keymaps (e.g. selecting choice nodes, expansion) see:
        --    https://github.com/L3MON4D3/LuaSnip?tab=readme-ov-file#keymaps
      },

      sources = cmp.config.sources({
        {
          name = 'lazydev',
          group_index = 0,
          priority = 1000,
          keyword_length = 2,
        },

        {
          name = 'nvim_lsp',
          group_index = 1,
          priority = 1000,
          keyword_length = 2,
          max_item_count = 30,
        },

        {
          name = 'vim-dadbod-completion',
          group_index = 1,
          priority = 950,
          keyword_length = 2,
        },

        {
          name = 'nvim_lsp_signature_help',
          group_index = 1,
          priority = 900,
          keyword_length = 2,
        },

        {
          name = 'luasnip',
          group_index = 1,
          priority = 850,
          keyword_length = 2,
          max_item_count = 10,
        },
      }, {
        {
          name = 'path',
          priority = 700,
          keyword_length = 2,
          max_item_count = 15,
          option = {
            trailing_slash = true,
            label_trailing_slash = true,
          },
        },

        {
          name = 'buffer',
          priority = 600,
          keyword_length = 2,
          max_item_count = 15,
          option = {
            get_bufnrs = function()
              local bufs = {}
              for _, win in ipairs(vim.api.nvim_list_wins()) do
                local buf = vim.api.nvim_win_get_buf(win)
                local buf_ft = vim.bo[buf].filetype
                if buf_ft ~= 'help' and buf_ft ~= 'qf' and buf_ft ~= 'nofile' then
                  bufs[buf] = true
                end
              end
              return vim.tbl_keys(bufs)
            end,
          },
        },
      }, {
        {
          name = 'cmdline',
          priority = 500,
          keyword_length = 1,
          max_item_count = 5,
        },
      }),

      window = {
        completion = cmp.config.window.bordered {
          border = 'rounded',
          scrollbar = false,
          col_offset = -3,
          side_padding = 1,
        },

        documentation = cmp.config.window.bordered {
          border = 'rounded',
          max_width = 80,
          max_height = 20,
        },
      },

      formatting = {
        fields = { 'kind', 'abbr', 'menu' },
        format = function(entry, vim_item)
          local kind_icons = {
            Text = '󰉿',
            Method = '󰆧',
            Function = '󰊕',
            Constructor = '',
            Field = '󰜢',
            Variable = '󰀫',
            Class = '󰠱',
            Interface = '',
            Module = '',
            Property = '󰜢',
            Unit = '󰑭',
            Value = '󰎠',
            Enum = '',
            Keyword = '󰌋',
            Snippet = '',
            Color = '󰏘',
            File = '󰈙',
            Reference = '󰈇',
            Folder = '󰉋',
            EnumMember = '',
            Constant = '󰏿',
            Struct = '󰙅',
            Event = '',
            Operator = '󰆕',
            TypeParameter = '',
          }

          vim_item.kind = string.format('%s %s', kind_icons[vim_item.kind] or '', vim_item.kind)

          vim_item.menu = ({
            nvim_lsp = '[LSP]',
            luasnip = '[Snippet]',
            buffer = '[Buffer]',
            path = '[Path]',
            lazydev = '[LazyDev]',
          })[entry.source.name]

          return vim_item
        end,
      },

      experimental = {
        ghost_text = true,
      },

      sorting = {
        comparators = {
          cmp.config.compare.offset,
          cmp.config.compare.exact,
          cmp.config.compare.score,
          require('cmp-under-comparator').under,
          cmp.config.compare.recently_used,
          cmp.config.compare.locality,
          cmp.config.compare.kind,
          cmp.config.compare.sort_text,
          cmp.config.compare.length,
          cmp.config.compare.order,
        },
      },

      performance = {
        debounce = 80,
        throttle = 30,
        fetching_timeout = 400,
        confirm_resolve_timeout = 80,
        async_budget = 1,
        max_view_entries = 50,
      },
    }
  end,
}
