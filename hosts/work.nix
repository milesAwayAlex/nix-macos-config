# Work laptop (MDM-managed). Host-specific quirks land here; everything
# portable belongs in modules/.
{ lib, ... }:
{
  nixpkgs.hostPlatform = "aarch64-darwin";

  system.primaryUser = "alexm";
  users.users.alexm.home = "/Users/alexm";

  # Homebrew's prefix predates this config, so nix-homebrew adopts it rather
  # than refusing to start. Adoption deletes only the git-tracked files of the
  # brew checkout; everything Homebrew keeps as ignored state — Cellar,
  # Caskroom, bin, Library/Taps — survives untouched (D16).
  nix-homebrew.user = "alexm";
  nix-homebrew.autoMigrate = true;

  # Brew packages this machine keeps that are not part of the shared
  # appliance set. Empty today, and the list only matters once
  # `homebrew.onActivation.cleanup` is turned on — at which point anything
  # unnamed is uninstalled. Manual installs (Docker, Rancher Desktop) have
  # no brew receipt and are invisible to cleanup, so they need no entry.
  homebrew.brews = [ ];
  homebrew.casks = [ ];

  # Employer-coupled configuration, kept together: the tools, and the licence
  # exception one of them needs. `op` is unfree, and with
  # `useGlobalPkgs = true` home-manager evaluates against nix-darwin's
  # nixpkgs — so the predicate has to be set from this layer even though the
  # package is declared in a home module (D18).
  home-manager.users.alexm.imports = [ ../modules/home/work.nix ];
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      # nixpkgs extracts AgileBits' own signed `op` from their pkg and leaves
      # it unstripped, so the desktop app still verifies the binary. The cask
      # is not self-updating, which is what rules it out under D16.
      "1password-cli"
    ];

  # Compat marker, set once at this host's first install and then left
  # alone; the other host keeps its own value when it's ported in.
  system.stateVersion = 7;
}
