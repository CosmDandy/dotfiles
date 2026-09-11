-- Custom schemas, merged ON TOP of the schemastore catalogue where they are more precise
-- (.tpl globs for GitHub Actions, ansible playbooks, CRDs).

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

-- NOTE: a key equal to a schemastore URL REPLACES that entry's globs; any other URL for
-- the same schema attaches it a second time (GitHub Workflow did, as json.* and www.*).
-- Compose has no entry at all: the catalogue already maps docker-compose*/compose*.
-- NOTE: yamlls prefixes every glob with `**/` and matches with picomatch in bash mode, so
-- a single `*` also crosses `/`, and a `!` exclusion turns into `**/!…` and excludes
-- nothing — never write one here. picomatch runs without `dot`: a `*` right after `/`
-- skips dot-files, which need a `.*` glob of their own.
local custom_schemas = {
  ['https://www.schemastore.org/github-workflow.json'] = { '/.github/workflows/*.{yml,yaml}', '/.github/workflows/*.tpl' },
  -- GitLab CI, keyed by the catalogue's URL so these globs replace its entry: the files
  -- pulled in by include: (.gitlab/ci/, ci-cd/) and the shared templates, mostly
  -- dot-files like .kaniko.yaml, got no schema before.
  ['https://gitlab.com/gitlab-org/gitlab-foss/-/raw/master/app/assets/javascripts/editor/schema/ci.json'] = {
    '**/.gitlab-ci.yml',
    '**/.gitlab-ci.yaml',
    '**/*.gitlab-ci.yml',
    '**/*.gitlab-ci.yaml',
    '**/.gitlab/ci/*.{yml,yaml}',
    '**/ci-cd/*.{yml,yaml}',
    '**/ci-cd/**/.*.{yml,yaml}',
    '**/gitlab-templates/*.{yml,yaml}',
    '**/gitlab-templates/.*.{yml,yaml}',
  },
  -- replaces the catalogue's entry, so its site.yml globs are repeated here
  ['https://raw.githubusercontent.com/ansible/ansible-lint/main/src/ansiblelint/schemas/ansible.json#/$defs/playbook'] = {
    '**/*playbook*.yml',
    '**/*playbook*.yaml',
    '**/playbooks/*.yml',
    '**/playbooks/*.yaml',
    '**/site.yml',
    '**/site.yaml',
  },
  -- CRD schemas: the built-in kubernetes schema only knows core types. The globs follow
  -- the naming convention (file named after the kind).
  [crd 'argoproj.io/application_v1alpha1.json'] = {
    '**/argocd/*.yaml',
    '**/bootstrap/root-app.yaml',
  },
  [crd 'gateway.networking.k8s.io/gateway_v1.json'] = { '**/gateway.yaml' },
  [crd 'gateway.networking.k8s.io/gatewayclass_v1.json'] = { '**/gatewayclass.yaml' },
  [crd 'gateway.networking.k8s.io/httproute_v1.json'] = { '**/*httproute*.yaml' },
  [crd 'gateway.networking.k8s.io/referencegrant_v1beta1.json'] = { '**/*referencegrant*.yaml' },

  -- NOTE: 'kubernetes' is yamlls's built-in trigger — a special mode that picks the schema
  -- by GVK. The cost: the schema is fetched over the network, ~4-5s on the first k8s file
  -- per session. Directory globs (k8s/, gitops/, manifests/) stamped it onto ArgoCD apps,
  -- kustomizations and chart values as well, so core manifests are added to it per file,
  -- by content, in on_attach below; only the explicit naming convention stays a glob.
  kubernetes = { '**/*.k8s.yaml' },
}

-- The built-in API groups the kubernetes schema knows; any other group is a CRD.
local core_groups = {}
for _, g in ipairs {
  '',
  'apps',
  'batch',
  'autoscaling',
  'policy',
  'networking.k8s.io',
  'rbac.authorization.k8s.io',
  'storage.k8s.io',
  'scheduling.k8s.io',
  'coordination.k8s.io',
  'discovery.k8s.io',
  'node.k8s.io',
  'certificates.k8s.io',
  'admissionregistration.k8s.io',
  'apiextensions.k8s.io',
  'apiregistration.k8s.io',
  'events.k8s.io',
  'flowcontrol.apiserver.k8s.io',
  'resource.k8s.io',
} do
  core_groups[g] = true
end

local function is_core_manifest(bufnr)
  local api, kind
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, 40, false)) do
    api = api or line:match '^apiVersion:%s*["\']?([%w%./-]+)'
    kind = kind or line:match '^kind:%s*%w'
    if api and kind then
      return core_groups[api:match '^(.*)/[^/]+$' or ''] == true
    end
  end
  return false
end

return {
  filetypes = { 'yaml', 'yaml.ansible', 'yaml.docker-compose', 'yaml.helm-values' },

  -- NOTE: before_init runs inside client:initialize(), after lazy.nvim has loaded plugins
  -- on BufReadPre — so require('schemastore') is safe here even with lazy = true, unlike
  -- a call in the table body.
  before_init = function(_, new_config)
    new_config.settings = new_config.settings or {}
    new_config.settings.yaml = new_config.settings.yaml or {}
    -- schemastore covers everything, custom_schemas win on the same key
    local schemas = require('schemastore').yaml.schemas()
    -- Symfony's **/config/services.yaml glob caught a Homepage dashboard config
    for url in pairs(schemas) do
      if url:find('symfony', 1, true) and url:find('services.schema.json', 1, true) then
        schemas[url] = nil
      end
    end
    for url, globs in pairs(custom_schemas) do
      schemas[url] = vim.deepcopy(globs)
    end
    new_config.settings.yaml.schemas = schemas
  end,

  -- A core manifest gets the kubernetes schema wherever it lives (sandbox/, the root of a
  -- repo), without a directory glob that would also catch CRDs and values files.
  on_attach = function(client, bufnr)
    local path = vim.api.nvim_buf_get_name(bufnr)
    if path == '' or not is_core_manifest(bufnr) then
      return
    end
    -- NOTE: the absolute path, not a root-relative one — yamlls prefixes `**/` to every
    -- glob, so a root-level 'deploy.yaml' would stamp the schema on every deploy.yaml at
    -- any depth. Glob metacharacters in the path would be read as a pattern.
    if path:find '[%[%]{}()*?!]' then
      return
    end
    local schemas = client.settings.yaml.schemas
    if not vim.tbl_contains(schemas.kubernetes, path) then
      table.insert(schemas.kubernetes, path)
      client:notify('workspace/didChangeConfiguration', { settings = client.settings })
    end
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
