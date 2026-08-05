return {
  filetypes = { 'yaml.ansible' },
  settings = {
    ansible = {
      ansible = { path = 'ansible' },
      executionEnvironment = { enabled = false },
      python = { interpreterPath = 'python3' },
      -- lint отдан nvim-lint (live по TextChanged, единообразно с yaml/tf/docker);
      -- здесь оставляем только синтаксическую валидацию LSP, чтобы не было
      -- дублирующихся ansible-lint диагностик на один таск.
      validation = {
        enabled = true,
        lint = { enabled = false },
      },
    },
  },
}
