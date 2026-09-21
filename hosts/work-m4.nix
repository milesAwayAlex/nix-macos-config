# Work laptop #2 (M4 Pro, MDM-managed). Only what this machine alone knows;
# the employer's configuration, shared with `work`, is modules/darwin/work.nix.
{ ... }:
{
  imports = [ ../modules/darwin/work.nix ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.primaryUser = "alex";

  # Host-owned like `system.stateVersion` below (D25).
  home-manager.sharedModules = [ { home.stateVersion = "26.05"; } ];

  # Compat marker, host-owned (D25): the maximum of the day at this host's
  # first install, never moved; the other hosts keep their own.
  system.stateVersion = 7;
}
