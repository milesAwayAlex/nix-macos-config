# Home-manager entry point.
{ ... }:
{
  imports = [
    ./pkgs.nix
    ./karabiner
  ];

  programs.home-manager.enable = true;

  home.stateVersion = "26.05";
}
