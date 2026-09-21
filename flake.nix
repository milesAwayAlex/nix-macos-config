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
    # Owns the Homebrew *installation* so a fresh machine needs no curl-bash
    # (D16). Deliberately outside the release train — it has no nixpkgs input
    # to follow, only a pin of Homebrew/brew itself.
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # The lima guest protocol — user creation, the cidata mounts, the guest
    # agent — as a NixOS module. Tracks lima's guest contract, which moves on
    # lima's schedule and not on the release train's, so it is pinned on its
    # own. Only `nixosModules.lima` is used, a pure module, so this input's own
    # nixpkgs is never evaluated.
    nixos-lima = {
      url = "github:nixos-lima/nixos-lima";
      # Only the module is used and it takes `pkgs` from us, so following keeps
      # a second nixpkgs out of the lock rather than changing what is built.
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
      # One entry per Mac, keyed by the alias it is switched as
      # (`--flake .#<name>`), never a hostname. The common list is every module
      # every machine runs; `hosts/<name>.nix` states what only that machine
      # knows and imports what only it runs (D25).
      darwinConfigurations = nixpkgs.lib.genAttrs [ "work" "work-m4" "personal" ] (
        name:
        nix-darwin.lib.darwinSystem {
          # `self` so a host can name the guest it runs (`devvm.guest`).
          specialArgs = { inherit self; };
          modules = [
            ./modules/darwin/core.nix
            ./modules/darwin/chrome.nix
            ./modules/darwin/devvm.nix
            ./modules/darwin/dns.nix
            ./modules/darwin/homebrew.nix
            ./modules/darwin/input
            ./modules/darwin/pam.nix
            ./modules/darwin/preferences.nix
            inputs.nix-homebrew.darwinModules.nix-homebrew
            ./hosts/${name}.nix
            home-manager.darwinModules.home-manager
            (
              { config, ... }:
              let
                user = config.system.primaryUser;
              in
              {
                # The host names its user once; everything else is spelled
                # from it, so no file carries a second copy (D25).
                users.users.${user}.home = "/Users/${user}";
                nix-homebrew.user = user;
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.users.${user} = import ./modules/home;
                # vim.nix takes the plugin source as a module arg (D11);
                # consumers of homeModules.vim pass their own.
                home-manager.extraSpecialArgs = {
                  vim9-lsp = inputs.vim9-lsp;
                };
                # What the justfile reads to pick the host. Set by hand once,
                # before a machine's first switch (BOOTSTRAP.md).
                environment.variables.NIXHOST = name;
              }
            )
          ];
        }
      );

      # The development VM's guest OS (Phase 8, D22): a product, independent of
      # any Mac. Two role sets, and a Mac names the one it runs in `devvm.guest`.
      # The hostname is the attribute, which is how `nixos-rebuild --flake .`
      # finds the right one from the guest it is aimed at.
      nixosConfigurations =
        builtins.mapAttrs
          (
            name: roles:
            nixpkgs.lib.nixosSystem {
              modules = [
                inputs.nixos-lima.nixosModules.lima
                ./modules/nixos/devvm
                {
                  nixpkgs.hostPlatform = "aarch64-linux";
                  networking.hostName = name;
                  devvm = roles;
                }
              ];
            }
          )
          {
            devvm = {
              containers.enable = true;
              cluster.enable = true;
            };
            devvm-builder = { };
          };

      # Portable modules, exported by class (D8) for other flakes to consume.
      homeModules.alacritty = ./modules/home/alacritty.nix;
      homeModules.bash = ./modules/home/bash;
      homeModules.gcloud = ./modules/home/gcloud.nix;
      homeModules.gh = ./modules/home/gh.nix;
      homeModules.git = ./modules/home/git.nix;
      homeModules.glow = ./modules/home/glow.nix;
      homeModules.gnu = ./modules/home/gnu.nix;
      homeModules.k8s = ./modules/home/k8s.nix;
      homeModules.karabiner = ./modules/home/karabiner;
      homeModules.node = ./modules/home/node.nix;
      homeModules.packages = ./modules/home/pkgs.nix;
      homeModules.personal = ./modules/home/personal.nix;
      homeModules.ssh = ./modules/home/ssh.nix;
      homeModules.tmux = ./modules/home/tmux.nix;
      homeModules.vim = ./modules/home/vim;
      homeModules.work = ./modules/home/work.nix;
      nixosModules.devvm = ./modules/nixos/devvm;
      darwinModules.chrome = ./modules/darwin/chrome.nix;
      darwinModules.devvm = ./modules/darwin/devvm.nix;
      darwinModules.dns = ./modules/darwin/dns.nix;
      darwinModules.homebrew = ./modules/darwin/homebrew.nix;
      darwinModules.input = ./modules/darwin/input;
      darwinModules.pam = ./modules/darwin/pam.nix;
      darwinModules.postgresql = ./modules/darwin/postgresql.nix;
      darwinModules.preferences = ./modules/darwin/preferences.nix;
      darwinModules.redis = ./modules/darwin/redis.nix;
      darwinModules.work = ./modules/darwin/work.nix;

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
