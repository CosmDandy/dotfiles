{
  description = "Cross-platform configuration with nix-darwin and NixOS";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      nixpkgs,
      darwin,
      home-manager,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      # Linux user-env (DevPod/devcontainers): vscode — стандартный юзер
      # devcontainer-образов, cosmdandy — остальные linux-хосты,
      # cluster — рабочий сервер kvt-d-01.
      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      users = [
        "vscode"
        "cosmdandy"
        "cluster"
      ];
      profiles = [
        "core"
        "devops"
      ];
      mkHome =
        system: user: profile:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true; # terraform (BUSL)
          };
          extraSpecialArgs = { inherit profile; };
          modules = [
            ./home
            {
              home.username = user;
              home.homeDirectory = "/home/${user}";
            }
          ];
        };
      # Конфигурация — функция от (hostname, user), а не константа в файле:
      # primaryUser раньше жил как захардкоженная строка в darwin-configuration.nix,
      # и install-nix.sh переписывал её на месте через sed под текущего пользователя
      # (рабочее дерево после установки всегда dirty). Теперь primaryUser приходит
      # через specialArgs, sed не нужен. hostname передаётся отдельным параметром,
      # а не выводится из user — имя атрибута конфигурации (macbook-cosmdandy,
      # используется в install-nix.sh и updm) и networking.hostName были связаны
      # только через primaryUser и расходились бы на другом пользователе.
      # cpuCores/memoryGiB — характеристики железа. Их приходится объявлять, а не
      # определять: eval обязан быть воспроизводимым и одинаково считаться на
      # любой машине, поэтому число ядер и объём ОЗУ текущего хоста ему просто не
      # видны (`builtins.getEnv` требует --impure и в чистом флейке не вариант).
      # Зато от них считаются max-jobs/cores демона — см. darwin-configuration.nix.
      mkDarwin =
        {
          hostname,
          user,
          cpuCores,
          memoryGiB,
          system ? "aarch64-darwin",
        }:
        darwin.lib.darwinSystem {
          inherit system;
          specialArgs = {
            inherit
              user
              hostname
              cpuCores
              memoryGiB
              ;
          };
          modules = [
            ./darwin-configuration.nix
            home-manager.darwinModules.home-manager
            ({ config, ... }: {
              # Пользовательский слой (симлинки, activation-хуки) — те же модули,
              # что и Linux homeConfigurations; пакеты остаются в systemPackages
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                # существующие файлы/чужие симлинки уводятся в *.hm-backup,
                # а не валят активацию (как -b hm-backup в updl на Linux);
                # overwriteBackup: повторное появление файла (например, ssh
                # пересоздал) не должно падать на занятом *.hm-backup
                backupFileExtension = "hm-backup";
                overwriteBackup = true;
                users.${config.system.primaryUser}.imports = [ ./home/darwin.nix ];
              };
            })
          ];
        };
    in
    {
      # ===============================
      # macOS Configuration (M1)
      # ===============================
      # Имя атрибута сохранено (на него ссылаются updm, install-nix.sh,
      # документация) — меняется только способ получения primaryUser/hostName.
      darwinConfigurations.macbook-cosmdandy = mkDarwin {
        hostname = "macbook-cosmdandy";
        user = "cosmdandy";
        # MacBook Air M1: `sysctl -n hw.ncpu hw.memsize` → 8 ядер, 8 ГиБ
        cpuCores = 8;
        memoryGiB = 8;
      };

      # ===============================
      # Linux user environments (home-manager)
      # Атрибут: <user>-<profile>-<system>, напр. vscode-devops-x86_64-linux
      # ===============================
      homeConfigurations = lib.listToAttrs (
        lib.concatMap (
          system:
          lib.concatMap (
            user:
            map (profile: {
              name = "${user}-${profile}-${system}";
              value = mkHome system user profile;
            }) profiles
          ) users
        ) linuxSystems
      );

      # ===============================
      # `nix fmt` — без formatter.<system> команда не работает вообще.
      # Именно nixfmt (RFC 166), не nixfmt-classic: его же требует
      # custom/rules/nix.md (`nixfmt --check`) и он же добавлен в
      # environment.systemPackages. Все системы, которые флейк уже
      # поддерживает: aarch64-darwin + линуксовые из homeConfigurations.
      # ===============================
      formatter = lib.genAttrs ([ "aarch64-darwin" ] ++ linuxSystems) (
        system: (import nixpkgs { inherit system; }).nixfmt
      );
    };
}
