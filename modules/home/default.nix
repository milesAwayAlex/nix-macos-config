# Home-manager entry point. Near-empty on purpose: Phase 1 gates the
# plumbing; payloads (karabiner first) come after.
{ ... }:
{
  programs.home-manager.enable = true;

  home.stateVersion = "26.05";
}
