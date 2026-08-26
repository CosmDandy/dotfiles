local detail = false

return {
  'stevearc/oil.nvim',
  ---@module 'oil'
  ---@type oil.SetupOpts
  opts = {
    -- watch the directory for changes made outside nvim (terminal, git checkout)
    watch_for_changes = true,
    -- delete permanently, not to the system trash
    delete_to_trash = false,
    skip_confirm_for_simple_edits = true,
    -- moving a file triggers LSP willRename, so references and imports follow
    lsp_file_methods = { autosave_changes = true },
    view_options = {
      show_hidden = true,
      -- natural number order: file2 before file10
      natural_order = true,
    },
    keymaps = {
      -- NOTE: <C-h> is left to window navigation — otherwise oil opens the file in a
      -- horizontal split instead of moving down.
      ['<C-h>'] = false,
      ['<C-p>'] = 'actions.preview', -- preview without opening
      -- gd toggles the detail view (permissions/size/mtime)
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
  config = function(_, opts)
    require('oil').setup(opts)

    -- drop a .gitkeep into a freshly created directory, so an empty folder can be
    -- committed at all
    vim.api.nvim_create_autocmd('User', {
      pattern = 'OilActionsPost',
      callback = function(event)
        if event.data.err then
          return
        end
        for _, action in ipairs(event.data.actions or {}) do
          if action.type == 'create' and action.entry_type == 'directory' then
            local scheme, dir = require('oil.util').parse_url(action.url)
            -- local filesystem only: on remote adapters the path is not a file path
            if scheme == 'oil://' and dir then
              local path = vim.fn.fnamemodify(vim.uri_decode(dir), ':p') .. '.gitkeep'
              if vim.fn.filereadable(path) == 0 then
                vim.fn.writefile({}, path)
              end
            end
          end
        end
      end,
    })
  end,
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
