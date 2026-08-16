# Work laptop (MDM-managed). Host-specific quirks land here; everything
# portable belongs in modules/.
{ ... }:
{
  nixpkgs.hostPlatform = "aarch64-darwin";

  system.primaryUser = "alexm";
  users.users.alexm.home = "/Users/alexm";

  # Compat marker, set once at this host's first install and then left
  # alone; the other host keeps its own value when it's ported in.
  system.stateVersion = 7;
}
