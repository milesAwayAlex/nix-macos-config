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
    # yegappan/lsp, deliberately out-of-nixpkgs (D11). Pinned by flake.lock,
    # independent of the release train; bump via `just update vim9-lsp`.
    vim9-lsp = {
      url = "github:yegappan/lsp";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      ...
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
            # vim.nix takes the plugin source as a module arg (D11);
            # consumers of homeModules.vim pass their own.
            home-manager.extraSpecialArgs = {
              vim9-lsp = inputs.vim9-lsp;
            };
          }
        ];
      };

      # Portable modules, exported so other flakes (the `old` machine,
      # pre-Phase-6) can consume them as an input.
      homeModules.alacritty = ./modules/home/alacritty.nix;
      homeModules.bash = ./modules/home/bash;
      homeModules.gcloud = ./modules/home/gcloud.nix;
      homeModules.gh = ./modules/home/gh.nix;
      homeModules.git = ./modules/home/git.nix;
      homeModules.glow = ./modules/home/glow.nix;
      homeModules.k8s = ./modules/home/k8s.nix;
      homeModules.karabiner = ./modules/home/karabiner;
      homeModules.node = ./modules/home/node.nix;
      homeModules.packages = ./modules/home/pkgs.nix;
      homeModules.ssh = ./modules/home/ssh.nix;
      homeModules.tmux = ./modules/home/tmux.nix;
      homeModules.vim = ./modules/home/vim;
      darwinModules.input = ./modules/darwin/input;

      # Packages this repo maintains itself because nixpkgs has none (D14).
      packages.${system}.kube-fzf = pkgs.callPackage ./packages/kube-fzf.nix { };

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
