# Staples that need no configuration of their own. Anything carrying config
# gets its own module; this list is the remainder.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    cspell # spell-check staple; repo lint jobs shell out to it
    deno # staple runtime: markdown/json formatting and stray TS outside node projects
    fzf
    gitleaks
    hack-font # terminal font; HM copies it into ~/Library/Fonts/HomeManager
    htop
    jq
    just
    opentofu # terraform is BUSL/unfree; terraform-ls drives tofu fine
    ripgrep
    shellcheck # also bundled into bash-language-server's wrapper
    shfmt
    sqlfluff # SQL lint/format; no SQL language server until the postgres slice
    # The GitHub build of UTM carries no Sparkle updater, so a cask would
    # freeze it as surely as nix does — and nix at least moves it on a flake
    # update. HM links it into ~/Applications/Home Manager Apps.
    utm
    yq-go # mikefarah's yq (the `yq` attr is the unrelated python wrapper)
  ];
}
