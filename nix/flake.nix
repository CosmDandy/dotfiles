{
  description = "Cross-platform configuration with nix-darwin and NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    darwin.url = "github:LnL7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, darwin, ... }@inputs:
    {
      # ===============================
      # macOS Configuration (M1 only)
      # ===============================
      darwinConfigurations.default = darwin.lib.darwinSystem {
        modules = [ ./darwin-configuration.nix ];
        pkgs = nixpkgs.legacyPackages.aarch64-darwin;
        system = "aarch64-darwin";
      };
  }
}
