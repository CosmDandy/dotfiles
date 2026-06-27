-- Кастомные схемы: точнее/специфичнее, чем дефолт schemastore (k8s-триггер,
-- .tpl-гловы для GitHub Actions, ansible-плейбуки). Мержатся ПОВЕРХ каталога.

-- CRD-схемы кэшируются локально при сборке dev-контейнера (install.sh →
-- ~/.cache/yaml-schemas), чтобы не дёргать сеть на первом открытии после рестарта
-- и работать оффлайн. crd() отдаёт file://-путь если кэш есть, иначе фолбэк на URL
-- (на свежей машине до install.sh или при сбое загрузки — деградируем мягко).
local cache_dir = (vim.env.XDG_CACHE_HOME or (vim.env.HOME .. '/.cache')) .. '/yaml-schemas'
local function crd(rel)
  local p = cache_dir .. '/' .. rel
  if vim.uv.fs_stat(p) then
    return 'file://' .. p
  end
  return 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/' .. rel
end

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
  -- CRD-схемы (datreeio/CRDs-catalog): встроенная kubernetes-схема знает только core-типы.
  -- Globs — по конвенции имён (файл назван по kind). Новый CRD = добавь URL+glob сюда
  -- И исключение в kubernetes ниже (иначе двойной матч core+CRD → конфликт диагностик).
  -- ВНИМАНИЕ про globs: матчер yamlls (filePatternAssociation.js) не glob-движок —
  -- он делает *→.* и якорит на $. Значит `*` идёт СКВОЗЬ `/`, а `**/` = `.*/`
  -- требует слэш. Поэтому `**/argocd/*.yaml` (НЕ `/**/*.yaml`) — иначе файлы прямо
  -- в argocd/ (без подпапки) не матчатся, а вложенные `*.yaml` ловит и так.
  [crd 'argoproj.io/application_v1alpha1.json'] = {
    '**/argocd/*.yaml',
    '**/bootstrap/root-app.yaml',
  },
  [crd 'gateway.networking.k8s.io/gateway_v1.json'] = { '**/gateway.yaml' },
  [crd 'gateway.networking.k8s.io/gatewayclass_v1.json'] = { '**/gatewayclass.yaml' },
  [crd 'gateway.networking.k8s.io/httproute_v1.json'] = { '**/*httproute*.yaml' },
  [crd 'gateway.networking.k8s.io/referencegrant_v1beta1.json'] = { '**/*referencegrant*.yaml' },

  -- 'kubernetes' — встроенный триггер yamlls: спец-режим авто-подбора по GVK (kind).
  -- Даёт лучший completion/валидацию (плоский oneOf от all.json — наоборот, ломает:
  -- 0 подсказок + «matches multiple schemas»). Минус: схема тянется с сети ~4-5с при
  -- ПЕРВОМ k8s-файле за сессию (URL зашит в сервер, локально не переопределить),
  -- дальше кэш в памяти. Пре-варм см. в lsp.lua (опционально).
  kubernetes = {
    -- `**/dir/*.yaml` (НЕ `/**/*.yaml`): см. заметку про матчер выше — `*` сам
    -- идёт сквозь `/`, поэтому ловит и прямых детей dir/, и вложенные файлы.
    '**/*.k8s.yaml',
    '**/k8s/*.yaml',
    '**/kubernetes/*.yaml',
    '**/manifests/*.yaml',
    -- GitOps-деревья (ArgoCD/Flux): обычные манифесты под gitops/
    '**/gitops/*.yaml',
    -- …но НЕ helm-метаданные/чарты — иначе ложные ошибки на values/Chart
    -- (templates/ и так уходят в ft 'helm' → helm-ls, см. autocmds.lua):
    '!**/Chart.yaml',
    -- *values* (не values*): ловит и prod_values.yaml, и argocd-values.yaml —
    -- Helm не навязывает имя values-файла, якорный glob их пропускал.
    '!**/*values*.yaml',
    '!**/charts/**',
    '!**/templates/**',
    -- .Files-ассеты чартов (homepage/files/*): дашборд-конфиги, а не манифесты:
    '!**/files/**',
    -- …и НЕ CRD-файлы (их держат спец-схемы выше) — иначе двойной матч core+CRD:
    '!**/argocd/**',
    '!**/bootstrap/root-app.yaml',
    '!**/gateway.yaml',
    '!**/gatewayclass.yaml',
    '!**/*httproute*.yaml',
    '!**/*referencegrant*.yaml',
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
