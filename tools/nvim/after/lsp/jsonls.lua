return {
  -- schemastore is loaded in before_init, which is safe with lazy=true (see yamlls.lua)
  before_init = function(_, new_config)
    new_config.settings = new_config.settings or {}
    new_config.settings.json = new_config.settings.json or {}
    new_config.settings.json.schemas = require('schemastore').json.schemas()
  end,

  settings = {
    json = {
      validate = { enable = true },
      format = { enable = true, keepLines = false },
    },
  },
}
