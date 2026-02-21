-- Filetype detection
vim.filetype.add {
  extension = {
    nomad = 'hcl',
    j2 = 'jinja',
    tfvars = 'terraform', -- Terraform variables
    tftpl = 'terraform', -- Terraform templates
  },
  filename = {
    ['.terraformrc'] = 'hcl',
    ['.terraform.tfrc'] = 'hcl',
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

-- Команда для переключения темы
vim.api.nvim_create_user_command('ToggleBackground', function()
  vim.o.background = vim.o.background == 'dark' and 'light' or 'dark'
end, {})

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
