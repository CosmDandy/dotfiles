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
      # devcontainer-образов, cosmdandy — остальные linux-хосты.
      linuxSystems = [ "x86_64-linux" "aarch64-linux" ];
      users = [ "vscode" "cosmdandy" ];
      profiles = [ "base" "full" ];
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
          {
            nixpkgs.config.allowUnfree = true;
          }
        ];
      };

      # ===============================
      # Linux user environments (home-manager)
      # Атрибут: <user>-<profile>-<system>, напр. vscode-full-x86_64-linux
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
