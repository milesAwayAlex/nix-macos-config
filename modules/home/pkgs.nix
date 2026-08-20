# Packages from nixpkgs — packages only; configs migrate in Phase 4.
# Locked-nixpkgs versions verified >= the brew set they replace (2026-08-18).
# Note: brew's copies shadow these until uninstalled (/opt/homebrew/bin comes
# first in the interactive PATH).
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    deno # runtime + the TS/JS language server and formatter (see vim/)
    fzf
    gh
    gitleaks
    hack-font # terminal font; HM copies it into ~/Library/Fonts/HomeManager
    htop
    jq
    just
    kubernetes-helm
    opentofu # terraform is BUSL/unfree; terraform-ls drives tofu fine
    ripgrep
    shellcheck # also bundled into bash-language-server's wrapper
    shfmt
    sqlfluff # SQL lint/format; no SQL language server until the postgres slice
    yq-go # mikefarah's yq (the `yq` attr is the unrelated python wrapper)
  ];
}
