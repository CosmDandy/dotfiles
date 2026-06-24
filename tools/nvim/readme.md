# Requirements

- **tree-sitter CLI** — nvim-treesitter (ветка `main`) компилирует парсеры через него.
  Без него подсветка падает с ошибками сборки парсеров.
  - Linux: `npm install -g --prefix ~/.local tree-sitter-cli` (mason-пакет падает на aarch64) —
    автоматизировано в `platform/linux/install.sh`.
  - macOS: `brew install tree-sitter` (или npm как выше).
  - Должен быть в `$PATH` (например `~/.local/bin`).
- **Node.js/npm** — для tree-sitter CLI и части language servers.

Интересные плагины к которым я может быть когда нибудь вернусь:
- iamcco/markdown-preview.nvim
- epwalsh/obsidian.nvim
- sindrets/diffview.nvim
- Bekaboo/dropbar.nvim
- norcalli/nvim-colorizer.lua
- MagicDuck/grug-far.nvim
- akinsho/toggleterm.nvim

# TODO:
- необходимо настроить events
