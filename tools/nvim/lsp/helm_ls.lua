-- helm-ls запускает свой yaml-language-server как подпроцесс и проксирует к нему
-- запросы с учётом Go-шаблонов. Итог: в templates/*.yaml есть и автодополнение
-- .Values/.Release/функций (от helm-ls), и валидация/комплишн по k8s JSON-схеме
-- (от встроенного yamlls). Обычный yamlls к ft 'helm' НЕ цепляется (см. yamlls.lua —
-- filetypes только yaml/yaml.ansible), иначе был бы двойной аттач и мусорные ошибки.
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
        -- mason кладёт бинарь в PATH на старте nvim → имя без пути резолвится
        path = 'yaml-language-server',
        diagnosticsLimit = 50,
        showDiagnosticsDirectly = false,
        enabledForFilesGlob = '*.{yaml,yml}',
        initTimeoutSeconds = 3,
        config = {
          schemas = {
            -- встроенный k8s-триггер yamlls для всего под templates/ (от корня чарта)
            kubernetes = 'templates/**',
          },
          completion = true,
          hover = true,
        },
      },
    },
  },
}
