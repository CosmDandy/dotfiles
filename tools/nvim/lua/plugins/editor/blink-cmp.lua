-- blink.cmp — completion, replacing the nvim-cmp + cmp-* stack.
-- https://github.com/saghen/blink.cmp
-- The prebuilt binary is downloaded automatically; no Rust toolchain needed.
return {
  'saghen/blink.cmp',
  event = 'InsertEnter',
  version = '*',
  -- blink finds friendly-snippets on the rtp itself; LuaSnip is no longer needed
  dependencies = {
    'rafamadriz/friendly-snippets',
  },

  ---@module 'blink.cmp'
  ---@type blink.cmp.Config
  opts = {
    keymap = {
      preset = 'default',
      ['<Tab>'] = { 'accept', 'snippet_forward', 'fallback' },
      ['<S-Tab>'] = { 'snippet_backward', 'fallback' },
      ['<C-n>'] = { 'select_next', 'fallback' },
      ['<C-p>'] = { 'select_prev', 'fallback' },
      ['<C-l>'] = { 'snippet_forward', 'fallback' },
      ['<C-j>'] = { 'snippet_backward', 'fallback' },
    },

    -- native vim.snippet (default preset)
    snippets = { preset = 'default' },

    sources = {
      default = { 'lsp', 'path', 'snippets', 'lazydev', 'buffer' },
      providers = {
        lazydev = {
          name = 'LazyDev',
          module = 'lazydev.integrations.blink',
          score_offset = 100,
        },
        -- helm inherits the yaml snippets (the luasnip filetype_extend equivalent)
        snippets = {
          opts = {
            extended_filetypes = { helm = { 'yaml' } },
          },
        },
        -- paths relative to the project root rather than the file's folder, for monorepos
        path = {
          opts = {
            get_cwd = function(_)
              return vim.fn.getcwd()
            end,
          },
        },
        -- words from OPEN buffers as a fallback, ranked below LSP
        buffer = {
          min_keyword_length = 2,
          score_offset = -3,
          opts = {
            -- from every loaded normal buffer, not just the current one
            get_bufnrs = function()
              return vim.tbl_filter(function(b)
                return vim.bo[b].buftype == '' and vim.api.nvim_buf_is_loaded(b)
              end, vim.api.nvim_list_bufs())
            end,
          },
        },
      },
    },

    completion = {
      accept = { auto_brackets = { enabled = true } },
      list = { selection = { preselect = true, auto_insert = false } },
      menu = {
        border = 'rounded',
        scrollbar = false,
        draw = {
          columns = {
            { 'kind_icon', 'label', 'label_description', gap = 1 },
            { 'kind', 'source_name', gap = 1 },
          },
        },
      },
      documentation = {
        auto_show = false,
        window = {
          border = 'rounded',
          -- documentation opens to the right of the menu, not over the number column
          direction_priority = {
            menu_north = { 'e', 'w' },
            menu_south = { 'e', 'w' },
          },
        },
      },
    },

    signature = {
      enabled = true,
      window = { border = 'rounded' },
    },

    fuzzy = {
      implementation = 'rust',
      -- exact keyword matches (resource, apiVersion) rank first
      sorts = { 'exact', 'score', 'sort_text' },
    },
  },
  opts_extend = { 'sources.default' },
}
