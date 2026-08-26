-- helm-ls runs its own yaml-language-server as a subprocess and proxies requests to it
-- with Go templating in mind, so templates/*.yaml get both .Values/.Release completion
-- (from helm-ls) and k8s JSON-schema validation (from the inner yamlls).
-- NOTE: the ordinary yamlls does NOT attach to filetype 'helm' — its filetypes list is
-- yaml/yaml.ansible only — or there would be a double attach and junk errors.
return {
  filetypes = { 'helm' },
  settings = {
    ['helm-ls'] = {
      logLevel = 'info',
      valuesFiles = {
        mainValuesFile = 'values.yaml',
        lintOverlayValuesFile = 'values.lint.yaml',
        additionalValuesFilesGlobPattern = 'values*.yaml',
      },
      helmLint = {
        enabled = true,
      },
      yamlls = {
        enabled = true,
        -- mason puts the binary on PATH at nvim startup, so a bare name resolves
        path = 'yaml-language-server',
        diagnosticsLimit = 50,
        showDiagnosticsDirectly = false,
        enabledForFilesGlob = '*.{yaml,yml}',
        initTimeoutSeconds = 3,
        config = {
          schemas = {
            -- the built-in k8s trigger for everything under templates/, from the chart root
            kubernetes = 'templates/**',
          },
          completion = true,
          hover = true,
        },
      },
    },
  },
}
