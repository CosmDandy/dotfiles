return {
  {
    "lukas-reineke/indent-blankline.nvim",
    config = function()
      require("ibl").setup({
        exclude = {
          buftypes = {
            "terminal",
          },
          filetypes = {
            "",
            "norg",
            "help",
            "markdown",
            "dapui_scopes",
            "dapui_stacks",
            "dapui_watches",
            "dapui_breakpoints",
            "dapui_hover",
            "dap-repl",
            "LuaTree",
            "dbui",
            "term",
            "fugitive",
            "fugitiveblame",
            "NvimTree",
            "packer",
            "neotest-summary",
            "Outline",
            "lsp-installer",
            "mason",
          },
        },
      })
    end,
  },
}
