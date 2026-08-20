# Node from nixpkgs pinned to the LTS major
# One-off other majors: `nix shell nixpkgs#nodejs_20` (two nodejs packages in
# home.packages would collide on bin/node).
{ config, pkgs, ... }:
let
  npmPrefix = "${config.home.homeDirectory}/.npm-global";
in
{
  home.packages = with pkgs; [
    nodejs_22 # LTS until 2027-04; pinned to the major so a lock bump can't walk to 24
    cspell # repo lint jobs shell out to it
  ];

  # npm's default global prefix is inside the read-only store. Redirect it with
  # the env var, not ~/.npmrc: npm writes registry auth tokens into that file,
  # so HM must not own it.
  home.sessionVariables.NPM_CONFIG_PREFIX = npmPrefix;
  home.sessionPath = [ "${npmPrefix}/bin" ];
}
