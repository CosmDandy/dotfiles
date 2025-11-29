{
  description = "Cross-platform configuration with nix-darwin and NixOS";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { self, nixpkgs, darwin, ... }@inputs: {
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
  };
}
