return {
  filetypes = { 'yaml.ansible' },
  settings = {
    ansible = {
      ansible = { path = 'ansible' },
      executionEnvironment = { enabled = false },
      python = { interpreterPath = 'python3' },
      -- NOTE: linting belongs to nvim-lint (live on TextChanged, like yaml/tf/docker);
      -- only the LSP's syntactic validation stays here, or one task gets duplicate
      -- ansible-lint diagnostics.
      validation = {
        enabled = true,
        lint = { enabled = false },
      },
    },
  },
}
