# Packages from nixpkgs — packages only; configs migrate in Phase 4.
# Locked-nixpkgs versions verified >= the brew set they replace (2026-08-18).
# Note: brew's copies shadow these until uninstalled (/opt/homebrew/bin comes
# first in the interactive PATH).
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    fzf
    gh
    git
    gitleaks
    glow
    hack-font # terminal font; HM copies it into ~/Library/Fonts/HomeManager
    htop
    jq
    just
    ripgrep
    tmux
    yq-go # mikefarah's yq (the `yq` attr is the unrelated python wrapper)
  ];
}
