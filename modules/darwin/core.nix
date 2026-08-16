# Portable system layer: nix-darwin manages Nix itself; upgrades ride the
# rebuild train (PLAN.md, interpreter row).
{ lib, ... }:
{
  nix.enable = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Scheduled cleanup: drop generations older than 14d, weekly, then
  # deduplicate the store.
  nix.gc = {
    automatic = true;
    interval = {
      Weekday = 7;
      Hour = 3;
      Minute = 15;
    };
    options = "--delete-older-than 14d";
  };
  nix.optimise = {
    automatic = true;
    interval = {
      Weekday = 7;
      Hour = 4;
      Minute = 15;
    };
  };

  # Disk-space floor, independent of the schedule: any nix operation that
  # would leave less than min-free on the store volume triggers GC until
  # max-free is available. Policy is portable; the numbers are overridable
  # per host.
  nix.settings.min-free = lib.mkDefault (10 * 1024 * 1024 * 1024); # 10 GiB
  nix.settings.max-free = lib.mkDefault (20 * 1024 * 1024 * 1024); # 20 GiB
}
