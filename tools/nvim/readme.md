# Requirements

Ручных шагов нет — всё приезжает из nix и хуков home-manager:

- **tree-sitter CLI** — nvim-treesitter (ветка `main`) компилирует парсеры через него.
  Пакет `tree-sitter` объявлен в `platform/nix/home/default.nix` (corePackages),
  то есть попадает в `$PATH` из nix-профиля на обоих платформах.
- **Node.js/npm** — там же (`nodejs_24`), нужен части language servers и mason.
- **Плагины, парсеры, mason-пакеты** ставятся хуками активации
  (`platform/nix/home/hooks.nix`: `syncNvimPlugins`, `installMasonTools`)
  и запекаются в devcontainer-образ (`platform/linux/Dockerfile`).

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
