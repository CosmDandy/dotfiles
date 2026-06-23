-- blink.cmp — автодополнение (заменил стек nvim-cmp + cmp-*)
-- https://github.com/saghen/blink.cmp
-- Prebuilt бинарник для macOS arm64 скачивается автоматически (Rust на машине не нужен)
return {
  'saghen/blink.cmp',
  event = 'InsertEnter',
  version = '*',
  dependencies = {
    {
      'L3MON4D3/LuaSnip',
      version = 'v2.*',
      build = 'make install_jsregexp',
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
                'jinja2',
              },
            }
          end,
        },
      },
    },
  },

  ---@module 'blink.cmp'
  ---@type blink.cmp.Config
  opts = {
    keymap = {
      preset = 'default',
      ['<Tab>'] = { 'accept', 'fallback' },
      ['<C-n>'] = { 'select_next', 'fallback' },
      ['<C-p>'] = { 'select_prev', 'fallback' },
      ['<C-b>'] = { 'scroll_documentation_up', 'fallback' },
      ['<C-f>'] = { 'scroll_documentation_down', 'fallback' },
      ['<C-Space>'] = { 'show', 'show_documentation', 'hide_documentation' },
      ['<C-l>'] = { 'snippet_forward', 'fallback' },
      ['<C-j>'] = { 'snippet_backward', 'fallback' },
    },

    snippets = { preset = 'luasnip' },

    appearance = {
      use_nvim_cmp_as_default = false,
      nerd_font_variant = 'mono',
    },

    sources = {
      default = { 'lsp', 'path', 'snippets', 'lazydev' },
      providers = {
        lazydev = {
          name = 'LazyDev',
          module = 'lazydev.integrations.blink',
          score_offset = 100,
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
        window = { border = 'rounded' },
      },
      ghost_text = { enabled = false },
    },

    signature = {
      enabled = true,
      window = { border = 'rounded' },
    },

    fuzzy = {
      implementation = 'rust',
    },
  },
  opts_extend = { 'sources.default' },
}
