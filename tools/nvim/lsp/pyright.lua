return {
  settings = {
    python = {
      analysis = {
        typeCheckingMode = 'basic',
        autoImportCompletions = true,
        autoSearchPaths = true,
        useLibraryCodeForTypes = true,
        diagnosticMode = 'openFilesOnly',
        reportMissingImports = true,
        reportMissingTypeStubs = false,
        reportGeneralTypeIssues = true,
        reportOptionalMemberAccess = true,
        reportOptionalSubscript = true,
        reportPrivateImportUsage = false,
      },
      pythonPath = './venv/bin/python',
    },
  },
}
