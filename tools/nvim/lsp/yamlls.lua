-- Custom schemas, merged ON TOP of the schemastore catalogue where they are more precise
-- (the k8s trigger, .tpl globs for GitHub Actions, ansible playbooks).

-- CRD schemas are cached locally during the dev-container build so the first open after a
-- restart does not hit the network and works offline. crd() returns a file:// path when
-- the cache exists and degrades to the URL otherwise.
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
  -- CRD schemas: the built-in kubernetes schema only knows core types. The globs follow
  -- the naming convention (file named after the kind).
  -- NOTE: a new CRD needs BOTH a URL+glob here AND an exclusion in the kubernetes list
  -- below, or a file matches core and CRD at once and the diagnostics conflict.
  -- NOTE: yamlls's matcher is not a glob engine — it turns `*` into `.*` and anchors on
  -- `$`, so `*` crosses `/` while `**/` means `.*/` and REQUIRES a slash. Hence
  -- `**/argocd/*.yaml` and not `/**/*.yaml`: otherwise files directly in argocd/ do not
  -- match, while nested ones are caught by `*` anyway.
  [crd 'argoproj.io/application_v1alpha1.json'] = {
    '**/argocd/*.yaml',
    '**/bootstrap/root-app.yaml',
  },
  [crd 'gateway.networking.k8s.io/gateway_v1.json'] = { '**/gateway.yaml' },
  [crd 'gateway.networking.k8s.io/gatewayclass_v1.json'] = { '**/gatewayclass.yaml' },
  [crd 'gateway.networking.k8s.io/httproute_v1.json'] = { '**/*httproute*.yaml' },
  [crd 'gateway.networking.k8s.io/referencegrant_v1beta1.json'] = { '**/*referencegrant*.yaml' },

  -- NOTE: 'kubernetes' is yamlls's built-in trigger — a special mode that picks the schema
  -- by GVK. It gives the best completion and validation, whereas the flat oneOf from
  -- all.json does the opposite (zero suggestions plus "matches multiple schemas"). The
  -- cost: the schema is fetched over the network, ~4-5s on the first k8s file per session,
  -- and the URL is baked into the server so it cannot be overridden locally.
  kubernetes = {
    '**/*.k8s.yaml',
    '**/k8s/*.yaml',
    '**/kubernetes/*.yaml',
    '**/manifests/*.yaml',
    -- GitOps trees (ArgoCD/Flux): ordinary manifests under gitops/
    '**/gitops/*.yaml',
    -- but NOT helm metadata or charts, or values/Chart get false errors
    -- (templates/ already becomes filetype 'helm' and goes to helm-ls)
    '!**/Chart.yaml',
    -- NOTE: *values* rather than values* — Helm does not mandate the file name, so an
    -- anchored glob missed prod_values.yaml and argocd-values.yaml.
    '!**/*values*.yaml',
    '!**/charts/**',
    '!**/templates/**',
    -- .Files assets of charts are dashboard configs, not manifests
    '!**/files/**',
    -- and not the CRD files above, or they match core and CRD at once
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

  -- NOTE: before_init runs inside client:initialize(), after lazy.nvim has loaded plugins
  -- on BufReadPre — so require('schemastore') is safe here even with lazy = true, unlike
  -- a call in the table body.
  before_init = function(_, new_config)
    new_config.settings = new_config.settings or {}
    new_config.settings.yaml = new_config.settings.yaml or {}
    -- custom_schemas win ('force'), schemastore covers everything else
    new_config.settings.yaml.schemas = vim.tbl_deep_extend('force', require('schemastore').yaml.schemas(), custom_schemas)
  end,

  settings = {
    yaml = {
      -- NOTE: the catalogue is managed by schemastore.nvim, so the built-in schemaStore is
      -- off — otherwise schemas are duplicated and the plugin's select/ignore options break.
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
