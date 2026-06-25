-- basedpyright — строгий форк pyright (Pylance-фичи). Заменил pyright.
-- Интерпретатор определяется динамически: .venv → venv → $VIRTUAL_ENV → system
local function detect_python(root)
  -- root может прийти как vim.NIL (userdata) / nil — подстраховываемся
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
  settings = {
    python = {
      analysis = {
        typeCheckingMode = 'basic',
        autoImportCompletions = true,
        autoSearchPaths = true,
        useLibraryCodeForTypes = true,
        diagnosticMode = 'openFilesOnly',
        reportMissingImports = true,
        reportMissingTypeStubs = false,
        reportGeneralTypeIssues = true,
        reportOptionalMemberAccess = true,
        reportOptionalSubscript = true,
        reportPrivateImportUsage = false,
      },
    },
  },

  -- pythonPath решается на старте сервера от корня проекта
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
