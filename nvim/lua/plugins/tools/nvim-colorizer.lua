return {
  -- Подсветка цветовых кодов
  {
    "norcalli/nvim-colorizer.lua",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("colorizer").setup({
        -- Включить для всех файлов
        "*",
        -- Особые настройки для конкретных типов файлов
        css = { css = true, css_fn = true, },
        scss = { css = true, css_fn = true, },
        sass = { css = true, css_fn = true, },
        stylus = { css = true, css_fn = true, },
        vim = { names = true, },
        conf = { names = false, },
        -- HTML и подобные форматы с CSS внутри
        html = { css = true, },
        javascript = { css_fn = true, },
        javascriptreact = { css_fn = true, },
        typescript = { css_fn = true, },
        typescriptreact = { css_fn = true, },
        svelte = { css = true, css_fn = true, },
        vue = { css = true, css_fn = true, },
      }, {
        -- Опции (необязательно)
        RGB = true, -- #RGB hex коды
        RRGGBB = true, -- #RRGGBB hex коды
        RRGGBBAA = true, -- #RRGGBBAA hex коды
        rgb_fn = true, -- CSS rgb() и rgba()
        hsl_fn = true, -- CSS hsl() и hsla()
        css = true, -- Включить все CSS функции: rgb_fn, hsl_fn
        css_fn = true, -- Включить расширенные CSS функции
        mode = "background", -- Режим отображения: "foreground", "background"
        tailwind = true, -- Включить цвета Tailwind CSS
        sass = { enable = true, parsers = { "css" }, }, -- Включить SASS
        virtualtext = "■", -- Добавить виртуальный текст после кода цвета
      })
    end,
  },
}
