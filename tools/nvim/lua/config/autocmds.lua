-- Filetype detection

-- A play outside playbooks/ (site.yml, support/deploy.yml next to an ansible.cfg): the
-- document is a list whose items carry hosts: or import_playbook:.
local function ansible_play(_, bufnr)
  if not bufnr then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 60, false)
  for _, l in ipairs(lines) do
    if not (l:match '^%s*$' or l:match '^%s*#' or l:match '^%-%-%-') then
      if not l:match '^%- ' then
        return
      end
      break
    end
  end
  for _, l in ipairs(lines) do
    if l:match '^%- hosts:' or l:match '^  hosts:' or l:match '^[%- ] [%w_.]*import_playbook:' then
      return 'yaml.ansible'
    end
  end
end

-- inventory variables get the same ansible-lint rules as role vars; encrypted files (sops,
-- a whole-file ansible-vault) stay yaml — nothing in them for ansible-lint to read
local function ansible_vars(path, bufnr)
  if path:match '%.sops%.ya?ml$' then
    return
  end
  if bufnr and (vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ''):match '^%$ANSIBLE_VAULT' then
    return
  end
  return 'yaml.ansible'
end

-- helm only inside a chart: an ansible role's templates/, GitLab CI templates/ or a
-- Fluent Bit config are not Go templates
local function helm_in_chart(path)
  if vim.fs.root(path, 'Chart.yaml') then
    return 'helm'
  end
end

vim.filetype.add {
  extension = {
    nomad = 'hcl',
    j2 = 'jinja',
    tf = 'terraform',
    -- NOTE: .tfvars keeps nvim's own 'terraform-vars' — terraform-ls then checks the
    -- values against variables.tf instead of parsing the file as a module.
    tftpl = 'terraform',
    tpl = 'yaml',
  },
  filename = {
    ['.terraformrc'] = 'hcl',
    ['.terraform.tfrc'] = 'hcl',
    -- ansible-lint's config is YAML (schemastore has its schema); nvim reads it as conf
    ['.ansible-lint'] = 'yaml',
    -- INI; nvim leaves it 'cfg', which has no treesitter parser
    ['ansible.cfg'] = 'dosini',
  },
  -- NOTE: gitlab-ci stays plain yaml — yamlls picks its schema by glob.
  pattern = {
    -- compose gets its own filetype so docker-compose-language-service attaches (image
    -- and service-name completion) next to yamlls; nvim itself leaves it plain yaml
    ['docker%-compose.*%.ya?ml'] = 'yaml.docker-compose',
    ['compose.*%.ya?ml'] = 'yaml.docker-compose',
    -- a values file next to a Chart.yaml: helm-ls then links it with the templates
    ['.*values.*%.ya?ml'] = function(path)
      if vim.uv.fs_stat(vim.fs.dirname(path) .. '/Chart.yaml') then
        return 'yaml.helm-values'
      end
    end,
    ['.*playbook.*%.ya?ml'] = 'yaml.ansible',
    -- NOTE: a pattern without '/' is matched against the file name only, so the one
    -- above never sees the directory — playbooks/site.yml opened as plain yaml.
    ['.*/playbooks/.*%.ya?ml'] = 'yaml.ansible',
    -- role variables: ansible-lint's var-naming and yaml rules instead of bare yamllint
    ['.*/roles/.*/defaults/.*%.ya?ml'] = 'yaml.ansible',
    ['.*/roles/.*/vars/.*%.ya?ml'] = 'yaml.ansible',
    ['.*/roles/.*/meta/.*%.ya?ml'] = 'yaml.ansible',
    ['.*requirements.*%.ya?ml'] = 'yaml.ansible',
    ['.*roles/.*/tasks/.*%.ya?ml'] = 'yaml.ansible',
    ['.*roles/.*/handlers/.*%.ya?ml'] = 'yaml.ansible',
    ['.*/group_vars/.*%.ya?ml'] = ansible_vars,
    ['.*/host_vars/.*%.ya?ml'] = ansible_vars,
    ['.*%.ya?ml'] = ansible_play,
    -- NOTE: patterns of equal priority run in no fixed order; a role template must stay
    -- jinja even when it renders a play, hence the priority.
    ['.*/roles/.*/templates/.*%.ya?ml'] = { 'jinja', { priority = 1 } },
    ['.*/roles/.*/templates/.*%.tpl'] = { 'jinja', { priority = 1 } },
    -- Nomad agent configs rendered by a role: terraform fmt fails on {% %}
    ['.*/roles/.*/templates/.*%.hcl'] = { 'jinja', { priority = 1 } },
    ['.*/templates/.*%.ya?ml'] = helm_in_chart,
    ['.*/templates/.*%.tpl'] = helm_in_chart,
    -- GitHub Actions .tpl
    ['.*%.github/workflows/.*%.tpl'] = 'yaml',
    -- Ansible .tpl
    ['.*playbook.*%.tpl'] = 'yaml.ansible',
    ['.*/playbooks/.*%.tpl'] = 'yaml.ansible',
    ['.*requirements.*%.tpl'] = 'yaml.ansible',
    ['.*roles/.*/tasks/.*%.tpl'] = 'yaml.ansible',
    ['.*roles/.*/handlers/.*%.tpl'] = 'yaml.ansible',
  },
}

-- Autocommands

vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})

-- restore the cursor to its last position when reopening a file
vim.api.nvim_create_autocmd('BufReadPost', {
  desc = 'Restore last cursor position',
  group = vim.api.nvim_create_augroup('restore-cursor', { clear = true }),
  callback = function(args)
    local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
    local lcount = vim.api.nvim_buf_line_count(args.buf)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- reread files changed outside nvim (git pull/checkout in the terminal)
vim.api.nvim_create_autocmd({ 'FocusGained', 'TermClose', 'TermLeave' }, {
  desc = 'Check for external file changes',
  group = vim.api.nvim_create_augroup('checktime', { clear = true }),
  callback = function(args)
    if vim.bo[args.buf].buftype ~= 'nofile' then
      vim.cmd 'checktime'
    end
  end,
})

-- close scratch buffers with q
vim.api.nvim_create_autocmd('FileType', {
  desc = 'Close utility buffers with q',
  group = vim.api.nvim_create_augroup('q-close', { clear = true }),
  pattern = { 'help', 'qf', 'man', 'lspinfo', 'checkhealth', 'query', 'dap-float' },
  callback = function(args)
    vim.bo[args.buf].buflisted = false
    vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = args.buf, silent = true, desc = 'Close' })
  end,
})

-- Dim the editor when its tmux pane loses focus, in step with tmux's
-- window-style: the theme is transparent, so nvim keeps emitting a reset
-- background that tmux cannot shade. Same hex as tools/tmux/.tmux.conf —
-- one shade, two painters.
local focus_dim = vim.api.nvim_create_augroup('focus-dim', { clear = true })
local function set_editor_bg(bg)
  for _, name in ipairs { 'Normal', 'NormalNC', 'EndOfBuffer' } do
    local hl = vim.api.nvim_get_hl(0, { name = name })
    hl.bg = bg
    vim.api.nvim_set_hl(0, name, hl)
  end
end
vim.api.nvim_create_autocmd('FocusLost', {
  desc = 'Dim like an inactive tmux pane',
  group = focus_dim,
  callback = function()
    set_editor_bg(vim.o.background == 'dark' and '#073642' or '#eee8d5')
  end,
})
vim.api.nvim_create_autocmd('FocusGained', {
  desc = 'Undo the inactive-pane dimming',
  group = focus_dim,
  callback = function()
    set_editor_bg 'NONE'
  end,
})

-- reload the colorscheme when background flips
vim.api.nvim_create_autocmd('OptionSet', {
  pattern = 'background',
  group = vim.api.nvim_create_augroup('background-change', { clear = true }),
  callback = function()
    if vim.g.colors_name then
      vim.cmd.colorscheme(vim.g.colors_name)
    end
  end,
})

vim.api.nvim_create_user_command('ToggleBackground', function()
  vim.o.background = vim.o.background == 'dark' and 'light' or 'dark'
end, {})

vim.api.nvim_create_user_command('SetAnsible', function()
  vim.bo.filetype = 'yaml.ansible'
end, { desc = 'Set filetype to Ansible' })

vim.api.nvim_create_user_command('SetYamlSchema', function()
  local schemas = {
    { name = 'Ansible', ft = 'yaml.ansible' },
    { name = 'Plain YAML', ft = 'yaml' },
  }

  vim.ui.select(schemas, {
    prompt = 'Select YAML schema:',
    format_item = function(item)
      return item.name
    end,
  }, function(choice)
    if choice then
      vim.bo.filetype = choice.ft
      print('Filetype set to: ' .. choice.ft)
    end
  end)
end, { desc = 'Select YAML schema' })
