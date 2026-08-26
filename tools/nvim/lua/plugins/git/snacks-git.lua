-- snacks.lazygit + snacks.gitbrowse, replacing kdheepak/lazygit.nvim and gitlinker.
-- NOTE: another snacks fragment — lazy merges opts/keys with ui/snacks.lua.
return {
  'folke/snacks.nvim',
  opts = {
    -- lazygit in a terminal float — the same binary, opened inside nvim.
    -- NOTE: configure=false so snacks does NOT overwrite lazygit's theme with nvim's
    -- transparent colours; its own config is used instead.
    lazygit = {
      configure = false,
      win = { style = 'lazygit', border = 'rounded' },
    },
    -- gitbrowse: a permalink by SHA to the line or selection; notify shows the URL
    gitbrowse = {
      notify = true,
      what = 'permalink',
    },
  },
  keys = {
    {
      '<leader>gg',
      function()
        -- NOTE: the shell lg() wrapper does not apply here — snacks calls the binary
        -- directly, so the light/dark overlay is chosen by vim.o.background instead.
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
        -- copy the permalink to the system clipboard (open is redirected to setreg)
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
      function()
        Snacks.gitbrowse { what = 'permalink' }
      end,
      desc = '[G]it open in browser',
    },
  },
}
