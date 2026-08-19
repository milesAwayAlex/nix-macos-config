# Home-manager entry point.
{ ... }:
{
  imports = [
    ./pkgs.nix
    ./alacritty.nix
    ./bash
    ./git.nix
    ./karabiner
    ./ssh.nix
    ./tmux.nix
  ];

  programs.home-manager.enable = true;

  home.stateVersion = "26.05";
}
