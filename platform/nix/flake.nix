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
    # declarative partitioning for the NixOS stand; nixos-anywhere drives it
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      nixpkgs,
      darwin,
      home-manager,
      disko,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      # Linux user env (DevPod/devcontainers): vscode is the stock devcontainer user,
      # cosmdandy the other linux hosts, cluster the work server kvt-d-01.
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
      # NOTE: the configuration is a function of (hostname, user), not a constant —
      # primaryUser used to be a hardcoded string that install-nix.sh rewrote in place with
      # sed, leaving the working tree permanently dirty. hostname is its own parameter
      # rather than derived from user, because the attribute name (macbook-cosmdandy, used
      # by install-nix.sh and updm) and networking.hostName were linked only through
      # primaryUser and would drift on another user.
      # NOTE: cpuCores/memoryGiB are DECLARED, not detected — eval must be reproducible
      # and compute the same on any machine, so the current host's specs are invisible to
      # it (getEnv needs --impure). The daemon's max-jobs/cores are derived from them.
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
              # The user layer uses the same modules as the Linux homeConfigurations;
              # packages stay in systemPackages.
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                # NOTE: existing files and foreign symlinks are moved to *.hm-backup
                # instead of failing the activation, and overwriteBackup covers a file
                # reappearing (ssh recreating one) onto an occupied *.hm-backup.
                backupFileExtension = "hm-backup";
                overwriteBackup = true;
                users.${config.system.primaryUser}.imports = [ ./home/darwin.nix ];
              };
            })
          ];
        };
      # NixOS hosts. The user layer is the SAME ./home module set as the Linux
      # homeConfigurations and the darwin one — home-manager runs as a NixOS module
      # here, so `home-manager switch` is wrong on these hosts just as it is on macOS;
      # the entry point is `nixos-rebuild switch`.
      mkNixos =
        {
          hostname,
          user,
          profile,
          system ? "x86_64-linux",
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit user hostname; };
          modules = [
            disko.nixosModules.disko
            ./nixos
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                # see mkDarwin: activation must not die on a pre-existing file
                backupFileExtension = "hm-backup";
                overwriteBackup = true;
                extraSpecialArgs = { inherit profile; };
                users.${user}.imports = [ ./home ];
              };
            }
          ];
        };
    in
    {
      # macOS (M1). The attribute name is referenced by updm, install-nix.sh and the docs.
      darwinConfigurations.macbook-cosmdandy = mkDarwin {
        hostname = "macbook-cosmdandy";
        user = "cosmdandy";
        # MacBook Air M1: `sysctl -n hw.ncpu hw.memsize`
        cpuCores = 8;
        memoryGiB = 8;
      };

      # Proxmox stand (VMID 9002 on pve-local-l-02). Raised with nixos-anywhere, see
      # the README section "NixOS-стенд".
      nixosConfigurations.nixos-stand = mkNixos {
        hostname = "nixos-stand";
        user = "cosmdandy";
        profile = "devops";
      };

      # Linux user environments, attribute <user>-<profile>-<system>.
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

      # NOTE: without formatter.<system> the `nix fmt` command does not work at all.
      # nixfmt (RFC 166), not nixfmt-classic — the same one the rules and CI call.
      formatter = lib.genAttrs ([ "aarch64-darwin" ] ++ linuxSystems) (
        system: (import nixpkgs { inherit system; }).nixfmt
      );
    };
}
