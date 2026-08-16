# Home-manager entry point.
{ ... }:
{
  imports = [ ./karabiner ];

  programs.home-manager.enable = true;

  home.stateVersion = "26.05";
}
