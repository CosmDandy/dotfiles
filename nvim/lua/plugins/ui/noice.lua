-- Noice
--
-- Уведомления, командная строка и всплывающие окна [https://github.com/folke/noice.nvim]
-- В основе уведомлений лежит notify [https://github.com/rcarriga/nvim-notify]
--
return {
  'folke/noice.nvim',
  event = 'VeryLazy',
  dependencies = {
    'MunifTanjim/nui.nvim',
    'rcarriga/nvim-notify',
  },
  config = function()
    require('notify').setup {
      stages = 'fade',
      timeout = 3000,
      -- background_colour = '#000000',
      fps = 60,
      render = 'minimal',
    }

    require('noice').setup {
      lsp = {
        override = {
          ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
          ['vim.lsp.util.stylize_markdown'] = true,
          ['cmp.entry.get_documentation'] = true,
        },
      },
      -- Пресеты для удобства (без макро-рекординга)
      presets = {
        bottom_search = true, -- Поиск внизу
        command_palette = false, -- Отключаем командную палитру
        long_message_to_split = true, -- Длинные сообщения в сплите
        inc_rename = false,
        lsp_doc_border = true,
      },
    }
  end,
}
