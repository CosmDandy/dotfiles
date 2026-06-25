-- Кастомные схемы: точнее/специфичнее, чем дефолт schemastore (k8s-триггер,
-- .tpl-гловы для GitHub Actions, ansible-плейбуки). Мержатся ПОВЕРХ каталога.
local custom_schemas = {
  ['https://json.schemastore.org/github-workflow.json'] = { '/.github/workflows/*.{yml,yaml}', '/.github/workflows/*.tpl' },
  ['https://gitlab.com/gitlab-org/gitlab/-/raw/master/app/assets/javascripts/editor/schema/ci.json'] = {
    '**/.gitlab-ci.yml',
    '**/.gitlab-ci.yaml',
  },
  ['https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json'] = {
    '**/docker-compose*.yml',
    '**/docker-compose*.yaml',
    '**/compose.yml',
    '**/compose.yaml',
  },
  ['https://raw.githubusercontent.com/ansible/ansible-lint/main/src/ansiblelint/schemas/ansible.json#/$defs/playbook'] = {
    '**/*playbook*.yml',
    '**/*playbook*.yaml',
  },
  -- 'kubernetes' — встроенный триггер yamlls (не URL): тянет bundled k8s-схему
  kubernetes = {
    '**/*.k8s.yaml',
    '**/k8s/**/*.yaml',
    '**/kubernetes/**/*.yaml',
    '**/manifests/**/*.yaml',
  },
}

return {
  filetypes = { 'yaml', 'yaml.ansible' },

  -- before_init вызывается в client:initialize() — уже после того, как lazy.nvim
  -- догрузил плагины по BufReadPre, поэтому require('schemastore') здесь безопасен
  -- даже при lazy = true (в отличие от вызова в теле таблицы).
  before_init = function(_, new_config)
    new_config.settings = new_config.settings or {}
    new_config.settings.yaml = new_config.settings.yaml or {}
    -- custom_schemas выигрывают ('force'), schemastore закрывает всё остальное
    new_config.settings.yaml.schemas = vim.tbl_deep_extend('force', require('schemastore').yaml.schemas(), custom_schemas)
  end,

  settings = {
    yaml = {
      -- Каталогом управляет schemastore.nvim → встроенный schemaStore выключаем,
      -- иначе дубли схем и ломаются select/ignore опции плагина.
      schemaStore = {
        enable = false,
        url = '',
      },
      validate = true,
      completion = true,
      hover = true,
      format = {
        enable = true,
        singleQuote = false,
        bracketSpacing = true,
      },
      customTags = {
        '!vault',
        '!encrypted/pkcs1-oaep',
        '!reference sequence',
      },
    },
    redhat = { telemetry = { enabled = false } },
  },

  capabilities = {
    textDocument = {
      foldingRange = {
        dynamicRegistration = false,
        lineFoldingOnly = true,
      },
    },
  },
}
