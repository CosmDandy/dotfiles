-- Restart LSP clients by hand (<leader>lr, :TerraformInit).
-- NOTE: the built-in `:lsp restart` starts the new client only once the old process has
-- exited, and terraform-ls was still not gone 10 s after shutdown (verified twice; yamlls
-- came back at once): the buffer sat without a server. Here the new client starts right
-- away, next to the one shutting down.
return function(clients)
  for _, c in ipairs(clients) do
    local bufs, config = vim.tbl_keys(c.attached_buffers), c.config
    c:stop()
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
