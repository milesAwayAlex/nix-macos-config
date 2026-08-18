{
  description = "Declarative macOS machine configuration: nix-darwin + home-manager";

  inputs = {
    # 26.05 release train — matched set; bump all three together (PLAN.md).
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
    }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      darwinConfigurations.work = nix-darwin.lib.darwinSystem {
        modules = [
          ./modules/darwin/core.nix
          ./modules/darwin/input
          ./hosts/work.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.alexm = import ./modules/home;
          }
        ];
      };

      # Portable modules, exported so other flakes (the `old` machine,
      # pre-Phase-6) can consume them as an input.
      homeModules.karabiner = ./modules/home/karabiner;
      homeModules.packages = ./modules/home/pkgs.nix;
      darwinModules.input = ./modules/darwin/input;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.gitleaks
          pkgs.just
        ];
      };

      # `nix fmt` formats the whole tree: treefmt wrapping nixfmt (RFC 166).
      formatter.${system} = pkgs.nixfmt-tree;
    };
}
