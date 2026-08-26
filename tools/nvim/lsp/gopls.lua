-- Delta over the shipped nvim-lspconfig config. gopls is not installed by
-- mason here (mason would `go install` it, compiling for minutes in every
-- container) — it comes from nixpkgs, so lsp.lua enables it explicitly.
return {
  settings = {
    gopls = {
      -- Match conform: it runs the gofumpt binary on save, and LSP formatting
      -- (the fallback path, and what code actions use) must not disagree.
      gofumpt = true,

      -- staticcheck's analyzers on top of the default vet set. This is the
      -- single highest-value setting in the file: it catches the mistakes a
      -- newcomer to Go actually makes, at edit time rather than in review.
      staticcheck = true,
      analyses = {
        -- nil dereference reachable on some path — Go's most common panic
        nilness = true,
        unusedparams = true,
        -- assigned and never read: the counterpart to the compiler's
        -- unused-variable error, which does not cover struct fields
        unusedwrite = true,
        -- interface{} where the generic `any` is meant (Go 1.18+)
        useany = true,
      },

      -- Fills a completed function call with its parameters as snippet stops.
      -- Worth the noise while the standard library is still unfamiliar.
      usePlaceholders = true,

      -- Inferred types are invisible in Go's `:=` — the hints are what makes
      -- them readable. Off by default, toggled with <leader>th (lsp.lua).
      hints = {
        assignVariableTypes = true,
        compositeLiteralFields = true,
        constantValues = true,
        parameterNames = true,
        rangeVariableTypes = true,
      },

      -- Codelens is enabled per-buffer wherever the server offers it
      -- (lsp.lua, LspAttach). `test` puts a run action above each test func;
      -- `tidy` and `upgrade_dependency` act on go.mod from the editor.
      -- run_govulncheck stays off: it hits the network on every lens refresh.
      codelenses = {
        generate = true,
        test = true,
        tidy = true,
        upgrade_dependency = true,
      },
    },
  },
}
