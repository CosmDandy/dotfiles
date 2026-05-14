-- autopairs
-- https://github.com/windwp/nvim-autopairs
-- Интеграция со скобками после accept в blink.cmp делается через completion.accept.auto_brackets
return {
  'windwp/nvim-autopairs',
  event = 'InsertEnter',
  opts = {},
}
