# GNU userland, unprefixed, replacing the BSD tools macOS ships (D15).
#
# Scope: the nix profile sits ahead of /usr/bin and /bin in the interactive
# PATH, so these win in shells and everything they spawn — just recipes, git
# hooks, editor subshells. launchd services, GUI apps and anything invoking
# /usr/bin/sed by absolute path still get BSD.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    coreutils # also brings timeout and realpath, which macOS lacks entirely
    diffutils
    findutils # find/xargs; also shadows macOS `locate`, which has no GNU database
    gawk
    gnugrep
    gnumake
    gnused
    gnutar
  ];
}
