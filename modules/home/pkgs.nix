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
    yq-go # mikefarah's yq (the `yq` attr is the unrelated python wrapper)
  ];
}
