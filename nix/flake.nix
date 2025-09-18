{
  description = "Linux development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      # Функция для создания пакетов для определенной системы
      commonPackages = pkgs: with pkgs; [
        # Основные утилиты
        starship
        eza
        tmux
        btop
        lazygit
        lazydocker

        # Языки программирования
        nodejs
        python3
        uv
        lua
        luarocks

        # Поиск и навигация
        fd
        ripgrep

        # Редакторы
        neovim

        # История команд
        atuin

        # Сетевые утилиты
        iperf3

        # Системные утилиты
        git
        wget
        curl
      ];
    in
    {
      # ===============================
      # Development Shells (только для Linux)
      # ===============================
      devShells = {
        x86_64-linux.default =
          let pkgs = nixpkgs.legacyPackages.x86_64-linux;
          in pkgs.mkShell {
            buildInputs = commonPackages pkgs;
            shellHook = ''
              echo "🚀 Linux development environment ready!"
              echo "Available tools: $(echo $buildInputs | wc -w) packages"

              # Инициализируем starship и atuin в Nix окружении
              if command -v starship >/dev/null 2>&1; then
                eval "$(starship init zsh)"
              fi

              if command -v atuin >/dev/null 2>&1; then
                eval "$(atuin init zsh)"
              fi
            '';
          };

        aarch64-linux.default =
          let pkgs = nixpkgs.legacyPackages.aarch64-linux;
          in pkgs.mkShell {
            buildInputs = commonPackages pkgs;
            shellHook = ''
              echo "🚀 Linux ARM development environment ready!"
              echo "Available tools: $(echo $buildInputs | wc -w) packages"

              # Инициализируем starship и atuin в Nix окружении
              if command -v starship >/dev/null 2>&1; then
                eval "$(starship init zsh)"
              fi

              if command -v atuin >/dev/null 2>&1; then
                eval "$(atuin init zsh)"
              fi
            '';
          };
      };
    };
}
