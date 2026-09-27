-- ansible-lint installs the pinned requirements.yml into <project>/.ansible/collections,
-- while the server scans only ANSIBLE_COLLECTIONS_PATH (~/.ansible, /usr/share): modules
-- of project collections had no completion, hover or definition. The project's copy
-- goes first, so the server and ansible-lint agree on versions.
-- NOTE: ahead of, not instead of, what ansible would use — the variable overrides
-- collections_path in ansible.cfg, so that one (relative to the project) and an exported
-- variable are kept behind it.
local function collections_path(root)
  local project = root .. '/.ansible/collections'
  if not vim.uv.fs_stat(project) then
    return
  end
  local rest = vim.env.ANSIBLE_COLLECTIONS_PATH or vim.env.ANSIBLE_COLLECTIONS_PATHS
  local cfg = root .. '/ansible.cfg'
  if not rest and vim.fn.filereadable(cfg) == 1 then
    for _, line in ipairs(vim.fn.readfile(cfg)) do
      local value = line:match '^%s*collections_paths?%s*[=:]%s*(.-)%s*$'
      if value then
        rest = table.concat(
          vim.tbl_map(function(p)
            p = vim.fn.expand(p)
            return p:sub(1, 1) == '/' and p or vim.fs.normalize(vim.fs.joinpath(root, p))
          end, vim.split(value, ':', { trimempty = true })),
          ':'
        )
        break
      end
    end
  end
  return project .. ':' .. (rest or (vim.env.HOME .. '/.ansible/collections:/usr/share/ansible/collections'))
end

return {
  filetypes = { 'yaml.ansible' },

  -- NOTE: a cmd function, not before_init — the process is already running by then.
  cmd = function(dispatchers, config)
    local path = config.root_dir and collections_path(config.root_dir)
    return vim.lsp.rpc.start({ 'ansible-language-server', '--stdio' }, dispatchers, {
      cwd = config.root_dir,
      env = path and { ANSIBLE_COLLECTIONS_PATH = path },
    })
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
