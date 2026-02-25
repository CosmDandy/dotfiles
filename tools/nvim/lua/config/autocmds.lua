-- Filetype detection
vim.filetype.add {
  extension = {
    nomad = 'hcl',
    j2 = 'jinja',
    tfvars = 'terraform',
    tftpl = 'terraform',
  },
  filename = {
    ['.terraformrc'] = 'hcl',
    ['.terraform.tfrc'] = 'hcl',
    ['docker-compose.yml'] = 'yaml.docker-compose',
    ['docker-compose.yaml'] = 'yaml.docker-compose',
    ['compose.yml'] = 'yaml.docker-compose',
    ['compose.yaml'] = 'yaml.docker-compose',
    ['.gitlab-ci.yml'] = 'yaml.gitlab',
  },
  pattern = {
    ['.*playbook.*%.ya?ml'] = 'yaml.ansible',
    ['.*requirements.*%.ya?ml'] = 'yaml.ansible',
    ['.*roles/.*/tasks/.*%.ya?ml'] = 'yaml.ansible',
    ['.*roles/.*/handlers/.*%.ya?ml'] = 'yaml.ansible',
    ['docker%-compose%..*%.ya?ml'] = 'yaml.docker-compose',
    ['%.gitlab%-ci%..*%.ya?ml'] = 'yaml.gitlab',
  },
}

-- Autocommands

vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- Перезагрузка colorscheme при изменении background
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

vim.api.nvim_create_user_command('SetDockerCompose', function()
  vim.bo.filetype = 'yaml.docker-compose'
end, { desc = 'Set filetype to Docker Compose' })

vim.api.nvim_create_user_command('SetGitLabCI', function()
  vim.bo.filetype = 'yaml.gitlab'
end, { desc = 'Set filetype to GitLab CI' })

vim.api.nvim_create_user_command('SetAnsible', function()
  vim.bo.filetype = 'yaml.ansible'
end, { desc = 'Set filetype to Ansible' })

vim.api.nvim_create_user_command('SetYamlSchema', function()
  local schemas = {
    { name = 'Docker Compose', ft = 'yaml.docker-compose' },
    { name = 'GitLab CI', ft = 'yaml.gitlab' },
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

-- Автоматическое определение темы при старте и возврате фокуса
local function detect_terminal_background()
  -- Отправляем OSC 11 запрос цвета фона терминала
  io.write('\x1b]11;?\x1b\\')
  io.flush()
end

vim.api.nvim_create_autocmd({ 'VimEnter', 'FocusGained' }, {
  group = vim.api.nvim_create_augroup('auto-background-detection', { clear = true }),
  callback = function()
    detect_terminal_background()
  end,
})
