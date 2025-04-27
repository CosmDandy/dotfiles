return {
  {
    'stevearc/oil.nvim',
    ---@module 'oil'
    ---@type oil.SetupOpts
    opts = {
      default_file_explorer = true,
      columns = {
        "icon",
        -- "permissions",
        -- "size",
      },
      delete_to_trash = true,
      float = {
        max_width = 0.3,
        fit_content = true,
        position = 'left',
        win_options = {
          winblend = 10,
          winhighlight = "Normal:OilFloat,FloatBorder:OilBorder",
        },
        override = function(conf)
          -- -- Получаем информацию о текущем буфере oil.nvim
          -- local oil_bufnr = vim.api.nvim_get_current_buf()
          -- local line_count = vim.api.nvim_buf_line_count(oil_bufnr)
          --
          -- -- Ограничиваем высоту окна количеством файлов в директории
          -- -- и добавляем небольшой отступ (например, 2 строки)
          -- conf.height = math.min(line_count + 2, vim.o.lines - 4)

          -- Помещаем окно слева
          conf.relative = "editor"
          conf.col = 3
          conf.row = 1

          return conf
        end,
      },
      -- on_open = function()
      --   local bufnr = vim.api.nvim_get_current_buf()
      --   local line_count = vim.api.nvim_buf_line_count(bufnr)
      --
      --   -- Получаем текущий оконный ID (если используется floating window)
      --   local win_config = vim.api.nvim_win_get_config(win_id)
      --
      --   -- Устанавливаем новую высоту окна (ограничиваем до 20 строк)
      --   win_config.height = math.min(line_count, 20)
      --
      --   -- Применяем новую конфигурацию
      --   vim.api.nvim_win_set_config(win_id, win_config)
      -- end,
    },
    -- Optional dependencies
    dependencies = { { "echasnovski/mini.icons", opts = {} } },
    -- dependencies = { "nvim-tree/nvim-web-devicons" }, -- use if you prefer nvim-web-devicons
    -- Lazy loading is not recommended because it is very tricky to make it work correctly in all situations.
    keys = {
      {
        '\\',
        function()
          require("oil").open_float()
        end,
        desc = "Open oil.nvim in float",
        silent = true
      },
    },
    lazy = false,
  }
}
