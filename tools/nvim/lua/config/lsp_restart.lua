-- Restart LSP clients by hand (<leader>lr, :TerraformInit).
-- NOTE: the built-in `:lsp restart` left terraform-ls stopped and started nothing
-- (verified twice; yamlls came back fine): a server slow to exit is still listed, and
-- lsp.start's default reuse_client attaches the buffer to it again. So: stop, then start
-- afresh with a reuse_client that skips stopped clients.
return function(clients)
  for _, c in ipairs(clients) do
    local bufs, config = vim.tbl_keys(c.attached_buffers), c.config
    c:stop()
    vim.wait(5000, function()
      return c:is_stopped()
    end, 50)
    for _, b in ipairs(bufs) do
      -- NOTE: the root is found again: a terraform module opened before its init had no
      -- .terraform yet, and the old client's root is the repo (.git)
      local root = config.root_markers and vim.fs.root(b, config.root_markers) or config.root_dir
      vim.lsp.start(vim.tbl_extend('force', config, { root_dir = root }), {
        bufnr = b,
        reuse_client = function(client, cfg)
          return client.name == cfg.name and client.root_dir == cfg.root_dir and not client:is_stopped()
        end,
      })
    end
  end
end
