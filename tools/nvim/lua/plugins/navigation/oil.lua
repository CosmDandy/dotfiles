local detail = false

return {
  'stevearc/oil.nvim',
  ---@module 'oil'
  ---@type oil.SetupOpts
  opts = {
    -- следить за изменениями директории (создание/удаление файлов в терминале, git checkout)
    watch_for_changes = true,
    -- удаление безвозвратно (не в системную корзину)
    delete_to_trash = false,
    skip_confirm_for_simple_edits = true,
    -- при перемещении файлов oil дёргает LSP willRename → обновляются ссылки/импорты
    lsp_file_methods = { autosave_changes = true },
    view_options = {
      show_hidden = true,
      -- человекочитаемая сортировка чисел: file2 раньше file10
      natural_order = true,
    },
    keymaps = {
      -- не перехватывать <C-h>: отдаём его навигации по окнам (tmux-navigator вниз),
      -- иначе oil открывает файл в горизонтальном сплите вместо перехода вниз
      ['<C-h>'] = false,
      ['<C-p>'] = 'actions.preview', -- превью файла без открытия
      -- gd: переключить детальный вид (права/размер/mtime)
      ['gd'] = {
        desc = 'Toggle detail view',
        callback = function()
          detail = not detail
          if detail then
            require('oil').set_columns { 'icon', 'permissions', 'size', 'mtime' }
          else
            require('oil').set_columns { 'icon' }
          end
        end,
      },
    },
  },
  dependencies = {
    { 'echasnovski/mini.icons', opts = {} },
  },
  keys = {
    {
      '\\',
      function()
        require('oil').open()
      end,
      desc = 'Open oil.nvim',
      silent = true,
    },
  },
  lazy = false,
}
