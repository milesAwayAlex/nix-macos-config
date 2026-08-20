# Node from nixpkgs pinned to the LTS major. One-off other majors: `nix shell nixpkgs#nodejs_20`
# (two nodejs packages in home.packages would collide on bin/node).
{ config, pkgs, ... }:
let
  npmPrefix = "${config.home.homeDirectory}/.npm-global";
in
{
  home.packages = with pkgs; [
    nodejs_22 # LTS until 2027-04

    # pnpm resolves its own per-repo version: the packaged 11.x is a launcher
    # that re-execs whatever `packageManager` names, and stays 11.x where
    # nothing is pinned.
    pnpm
  ];

  # npm's default global prefix is inside the read-only store. Redirect it with
  # the env var, not ~/.npmrc: npm writes registry auth tokens into that file,
  # so HM must not own it.
  home.sessionVariables.NPM_CONFIG_PREFIX = npmPrefix;
  home.sessionPath = [ "${npmPrefix}/bin" ];
}
