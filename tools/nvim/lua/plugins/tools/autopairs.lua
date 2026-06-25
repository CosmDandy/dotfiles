-- autopairs
-- https://github.com/windwp/nvim-autopairs
-- Интеграция со скобками после accept в blink.cmp делается через completion.accept.auto_brackets
return {
  'windwp/nvim-autopairs',
  event = 'InsertEnter',
  opts = {
    -- treesitter-aware: не ставить пару внутри строк/комментариев
    check_ts = true,
    ts_config = {
      lua = { 'string' },
      python = { 'string', 'comment' },
      yaml = { 'block_scalar' },
    },
    -- <M-e>: обернуть уже набранный текст парой
    fast_wrap = {},
    -- где автопары не нужны (инпут пикера snacks и т.п.)
    disable_filetype = { 'TelescopePrompt', 'snacks_picker_input' },
  },
}
