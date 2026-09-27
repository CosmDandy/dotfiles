return {
  settings = {
    Lua = {
      completion = { callSnippet = 'Replace' },
      diagnostics = {
        disable = { 'missing-fields' },
        globals = { 'vim' },
      },
      workspace = { checkThirdParty = false },
    },
  },
}
