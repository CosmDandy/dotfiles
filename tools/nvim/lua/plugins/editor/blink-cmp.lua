-- blink.cmp — автодополнение (заменил стек nvim-cmp + cmp-*)
-- https://github.com/saghen/blink.cmp
-- Prebuilt бинарник для macOS arm64 скачивается автоматически (Rust на машине не нужен)
return {
  'saghen/blink.cmp',
  event = 'InsertEnter',
  version = '*',
  -- friendly-snippets (VSCode-формат) blink находит на rtp сам; LuaSnip больше не нужен
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
        -- helm наследует yaml-сниппеты (аналог luasnip filetype_extend); friendly-snippets blink грузит сам
        snippets = {
          opts = {
            extended_filetypes = { helm = { 'yaml' } },
          },
        },
        -- пути считать от корня проекта (cwd), а не от папки файла — для монорепо
        path = {
          opts = {
            get_cwd = function(_)
              return vim.fn.getcwd()
            end,
          },
        },
        -- слова из ОТКРЫТЫХ буферов (включая соседний сплит) — фолбэк, ранжируется ниже LSP
        buffer = {
          min_keyword_length = 2,
          score_offset = -3,
          opts = {
            -- брать из всех загруженных обычных буферов, а не только текущего
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
          -- открывать доку вправо от меню (не уезжать на колонку номеров слева)
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
      -- точные совпадения ключевых слов (resource, apiVersion) ранжируются первыми
      sorts = { 'exact', 'score', 'sort_text' },
    },
  },
  opts_extend = { 'sources.default' },
}
