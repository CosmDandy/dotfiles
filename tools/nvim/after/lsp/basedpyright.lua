-- basedpyright is the strict pyright fork with Pylance features; it replaced pyright.
-- The interpreter is resolved dynamically: .venv -> venv -> $VIRTUAL_ENV -> system.
local function detect_python(root)
  -- NOTE: root may arrive as vim.NIL (userdata) or nil, hence the guard
  if type(root) ~= 'string' then
    root = vim.fn.getcwd()
  end
  for _, rel in ipairs { '/.venv/bin/python', '/venv/bin/python' } do
    local p = root .. rel
    if vim.fn.executable(p) == 1 then
      return p
    end
  end
  if vim.env.VIRTUAL_ENV then
    local p = vim.env.VIRTUAL_ENV .. '/bin/python'
    if vim.fn.executable(p) == 1 then
      return p
    end
  end
  local sys = vim.fn.exepath 'python3'
  return sys ~= '' and sys or 'python'
end

return {
  -- NOTE: basedpyright reads only the basedpyright.* section; python.analysis.* is
  -- silently ignored and the server falls back to its strict 'recommended' mode.
  -- python.pythonPath (before_init below) is still read from the python section.
  settings = {
    basedpyright = {
      analysis = {
        typeCheckingMode = 'basic',
        autoImportCompletions = true,
        autoSearchPaths = true,
        useLibraryCodeForTypes = true,
        diagnosticMode = 'openFilesOnly',
        -- rule levels go through overrides, not as keys of analysis; 'basic' already
        -- reports missing imports and optional access, this is the one deviation
        diagnosticSeverityOverrides = {
          reportPrivateImportUsage = 'none',
        },
      },
    },
  },

  -- pythonPath is resolved from the project root when the server starts
  before_init = function(params, config)
    local root
    local wf = params.workspaceFolders
    if type(wf) == 'table' and type(wf[1]) == 'table' and type(wf[1].uri) == 'string' then
      root = vim.uri_to_fname(wf[1].uri)
    elseif type(params.rootPath) == 'string' then
      root = params.rootPath
    end
    config.settings = config.settings or {}
    config.settings.python = config.settings.python or {}
    config.settings.python.pythonPath = detect_python(root)
  end,
}
