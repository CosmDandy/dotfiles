return {
  {
    "gorbit99/codewindow.nvim",
    config = function()
      local codewindow = require("codewindow")
      codewindow.setup {
        window_border = vim.g.border_chars
      }
      codewindow.apply_default_keybinds()
    end,
  },
}
