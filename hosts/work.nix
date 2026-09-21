# Work laptop #1 (M1 Max, MDM-managed). Only what this machine alone knows;
# the employer's configuration, shared with `work-m4`, is
# modules/darwin/work.nix.
{ ... }:
{
  imports = [ ../modules/darwin/work.nix ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.primaryUser = "alexm";

  # Homebrew's prefix predates this config, so nix-homebrew adopts it rather
  # than refusing to start. Adoption deletes only the git-tracked files of the
  # brew checkout; everything Homebrew keeps as ignored state — Cellar,
  # Caskroom, bin, Library/Taps — survives untouched (D16).
  nix-homebrew.autoMigrate = true;

  # Host-owned like `system.stateVersion` below (D25).
  home-manager.sharedModules = [ { home.stateVersion = "26.05"; } ];

  # Compat marker, host-owned (D25): the maximum of the day at this host's
  # first install, never moved; the other hosts keep their own.
  system.stateVersion = 7;
}
