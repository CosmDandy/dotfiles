return {
  filetypes = { 'yaml', 'yaml.ansible' },
  settings = {
    yaml = {
      schemaStore = {
        enable = true,
        url = 'https://www.schemastore.org/api/json/catalog.json',
      },
      schemas = {
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
        kubernetes = {
          '**/*.k8s.yaml',
          '**/k8s/**/*.yaml',
          '**/kubernetes/**/*.yaml',
        },
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
  },
  capabilities = {
    textDocument = {
      completion = {
        completionItem = {
          documentationFormat = { 'markdown', 'plaintext' },
          snippetSupport = true,
        },
      },
    },
  },
}
