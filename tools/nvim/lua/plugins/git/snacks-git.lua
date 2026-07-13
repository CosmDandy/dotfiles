-- snacks.lazygit + snacks.gitbrowse — заменили kdheepak/lazygit.nvim и gitlinker.
-- Это ещё один фрагмент snacks: lazy мержит opts/keys с ui/snacks.lua и snacks-picker.lua.
return {
  'folke/snacks.nvim',
  opts = {
    -- lazygit как терминал-float (тот же бинарь lazygit, открыт внутри nvim).
    -- configure=false: НЕ перезаписывать тему lazygit прозрачными цветами nvim —
    -- берём его собственный ~/.config/lazygit (как было с kdheepak). border вернул контур.
    lazygit = {
      configure = false,
      win = { style = 'lazygit', border = 'rounded' },
    },
    -- gitbrowse: permalink (по SHA) на строку/выделение. notify показывает URL.
    gitbrowse = {
      notify = true,
      what = 'permalink',
    },
  },
  keys = {
    {
      '<leader>gg',
      function()
        -- В nvim обёртка lg() из шелла не работает (snacks зовёт бинарь напрямую).
        -- Подставляем light/dark-оверлей lazygit по vim.o.background — как lg() по OSC11.
        local d = vim.fn.expand '~/.config/lazygit'
        local overlay = (vim.o.background == 'light') and 'theme-light.yml' or 'theme-dark.yml'
        Snacks.lazygit { args = { '--use-config-file=' .. d .. '/config.yml,' .. d .. '/' .. overlay } }
      end,
      desc = 'Lazy[G]it',
    },
    {
      '<leader>gy',
      mode = { 'n', 'v' },
      function()
        -- скопировать permalink в системный буфер (open переопределён на setreg)
        Snacks.gitbrowse {
          what = 'permalink',
          open = function(url)
            vim.fn.setreg('+', url)
            vim.notify('Copied: ' .. url, vim.log.levels.INFO, { title = 'gitbrowse' })
          end,
        }
      end,
      desc = '[G]it [y]ank permalink',
    },
    {
      '<leader>gY',
      mode = { 'n', 'v' },
      function() Snacks.gitbrowse { what = 'permalink' } end,
      desc = '[G]it open in browser',
    },
  },
}
