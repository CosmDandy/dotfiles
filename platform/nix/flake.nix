{
  description = "Cross-platform configuration with nix-darwin and NixOS";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { self, nixpkgs, darwin, home-manager, ... }@inputs:
    let
      lib = nixpkgs.lib;
      # Linux user-env (DevPod/devcontainers): vscode — стандартный юзер
      # devcontainer-образов, cosmdandy — остальные linux-хосты,
      # cluster — рабочий сервер kvt-d-01.
      linuxSystems = [ "x86_64-linux" "aarch64-linux" ];
      users = [ "vscode" "cosmdandy" "cluster" ];
      profiles = [ "core" "devops" ];
      mkHome = system: user: profile:
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
    in {
      # ===============================
      # macOS Configuration (M1)
      # ===============================
      darwinConfigurations.macbook-cosmdandy = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          ./darwin-configuration.nix
          home-manager.darwinModules.home-manager
          ({ config, ... }: {
            nixpkgs.config.allowUnfree = true;
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

      # ===============================
      # Linux user environments (home-manager)
      # Атрибут: <user>-<profile>-<system>, напр. vscode-devops-x86_64-linux
      # ===============================
      homeConfigurations = lib.listToAttrs (lib.concatMap (system:
        lib.concatMap (user:
          map (profile: {
            name = "${user}-${profile}-${system}";
            value = mkHome system user profile;
          }) profiles
        ) users
      ) linuxSystems);
    };
}
