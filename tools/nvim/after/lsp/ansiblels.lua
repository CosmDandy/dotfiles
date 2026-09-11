return {
  filetypes = { 'yaml.ansible' },

  -- ansible-lint installs the pinned requirements.yml into <project>/.ansible/collections,
  -- while the server scans only ANSIBLE_COLLECTIONS_PATH (~/.ansible, /usr/share): modules
  -- of project collections had no completion, hover or definition. The project's copy
  -- goes first, so the server and ansible-lint agree on versions.
  -- NOTE: a cmd function, not before_init — the process is already running by then.
  cmd = function(dispatchers, config)
    local env
    if config.root_dir then
      env = {
        ANSIBLE_COLLECTIONS_PATH = table.concat({
          config.root_dir .. '/.ansible/collections',
          vim.env.HOME .. '/.ansible/collections',
          '/usr/share/ansible/collections',
        }, ':'),
      }
    end
    return vim.lsp.rpc.start({ 'ansible-language-server', '--stdio' }, dispatchers, { cwd = config.root_dir, env = env })
  end,

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
