# Personal laptop (M4). Host-specific facts land here; everything portable
# belongs in modules/.
{ self, ... }:
{
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.primaryUser = "alex";

  # The password manager is per host (D19): its cask, its browser extension and
  # its agent socket (modules/home/personal.nix) sit together. The desktop app
  # is what serves ssh and lets the extension unlock by Touch ID. iina beside
  # it: both self-update, which is the cask test (D16).
  homebrew.casks = [
    "bitwarden"
    "iina"
  ];
  system.defaults.CustomSystemPreferences."/Library/Preferences/com.google.Chrome".ExtensionInstallForcelist =
    [
      # Force-installed so a fresh profile arrives with it; the suffix is
      # Chrome's own extension update service.
      "nngceckbapebfimnlniiiahkandclblb;https://clients2.google.com/service/update2/crx"
    ];

  home-manager.sharedModules = [
    ../modules/home/personal.nix
    # Host-owned like `system.stateVersion` below (D25).
    { home.stateVersion = "26.05"; }
  ];

  # Builder only (PLAN.md Phase 6): aarch64-linux derivations, image builds
  # for UTM among them, which is what nested virtualization (on by default)
  # is for. No shared directory and no registries — a builder needs nothing
  # from the host. Sized for that: the load is a build, not a cluster.
  devvm = {
    enable = true;
    guest = self.nixosConfigurations.devvm-builder;
    cpus = 4;
    memory = "8GiB";
  };

  # Compat marker, host-owned (D25): the maximum of the day at this host's
  # first install, never moved; the other host keeps its own.
  system.stateVersion = 7;
}
