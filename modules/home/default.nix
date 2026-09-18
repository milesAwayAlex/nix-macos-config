# Home-manager entry point: the set every host takes. Host-coupled modules —
# the employer's, a password manager's — and `home.stateVersion` are declared
# by the host file through `home-manager.sharedModules` (D25).
{ ... }:
{
  imports = [
    ./pkgs.nix
    ./alacritty.nix
    ./bash
    ./gh.nix
    ./git.nix
    ./glow.nix
    ./gnu.nix
    ./karabiner
    ./node.nix
    ./ssh.nix
    ./tmux.nix
    ./vim
  ];

  programs.home-manager.enable = true;
}
