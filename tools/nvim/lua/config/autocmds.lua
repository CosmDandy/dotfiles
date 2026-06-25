-- Filetype detection
vim.filetype.add {
  extension = {
    nomad = 'hcl',
    j2 = 'jinja',
    tf = 'terraform',
    tfvars = 'terraform',
    tftpl = 'terraform',
    tpl = 'yaml',
  },
  filename = {
    ['.terraformrc'] = 'hcl',
    ['.terraform.tfrc'] = 'hcl',
  },
  -- compose/gitlab-ci остаются обычным yaml — yamlls подбирает схему по glob (см. lsp.lua)
  pattern = {
    ['.*playbook.*%.ya?ml'] = 'yaml.ansible',
    ['.*requirements.*%.ya?ml'] = 'yaml.ansible',
    ['.*roles/.*/tasks/.*%.ya?ml'] = 'yaml.ansible',
    ['.*roles/.*/handlers/.*%.ya?ml'] = 'yaml.ansible',
    -- Helm (templates/ dir in charts)
    ['.*/templates/.*%.ya?ml'] = 'helm',
    ['.*/templates/.*%.tpl'] = 'helm',
    -- GitHub Actions .tpl
    ['.*%.github/workflows/.*%.tpl'] = 'yaml',
    -- Ansible .tpl
    ['.*playbook.*%.tpl'] = 'yaml.ansible',
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

-- Вернуть курсор на последнюю позицию при открытии файла
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

-- Перечитать файлы, изменённые извне (git pull/checkout в терминале)
vim.api.nvim_create_autocmd({ 'FocusGained', 'TermClose', 'TermLeave' }, {
  desc = 'Check for external file changes',
  group = vim.api.nvim_create_augroup('checktime', { clear = true }),
  callback = function(args)
    if vim.bo[args.buf].buftype ~= 'nofile' then
      vim.cmd 'checktime'
    end
  end,
})

-- Закрывать служебные буферы на q
vim.api.nvim_create_autocmd('FileType', {
  desc = 'Close utility buffers with q',
  group = vim.api.nvim_create_augroup('q-close', { clear = true }),
  pattern = { 'help', 'qf', 'man', 'lspinfo', 'checkhealth', 'startuptime', 'query', 'dap-float' },
  callback = function(args)
    vim.bo[args.buf].buflisted = false
    vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = args.buf, silent = true, desc = 'Close' })
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
