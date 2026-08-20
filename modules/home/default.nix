# Home-manager entry point.
{ ... }:
{
  imports = [
    ./pkgs.nix
    ./alacritty.nix
    ./bash
    ./gcloud.nix
    ./gh.nix
    ./git.nix
    ./glow.nix
    ./gnu.nix
    ./k8s.nix
    ./karabiner
    ./node.nix
    ./ssh.nix
    ./tmux.nix
    ./vim
  ];

  programs.home-manager.enable = true;

  home.stateVersion = "26.05";
}
