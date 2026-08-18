# Home-manager entry point.
{ pkgs, ... }:
{
  imports = [ ./karabiner ];

  programs.home-manager.enable = true;

  # Workflow staples: `just` drives the repo, `gitleaks` serves the
  # pre-commit hook without the `nix run` toll.
  home.packages = [
    pkgs.just
    pkgs.gitleaks
  ];

  home.stateVersion = "26.05";
}
