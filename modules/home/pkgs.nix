# Packages from nixpkgs — packages only; configs migrate in Phase 4.
# Locked-nixpkgs versions verified >= the brew set they replace (2026-08-18).
# Note: brew's copies shadow these until uninstalled (/opt/homebrew/bin comes
# first in the interactive PATH).
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    fzf
    git
    gitleaks
    glow
    just
    ripgrep
    tmux
  ];
}
