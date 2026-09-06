# Work laptop (MDM-managed). Host-specific quirks land here; everything
# portable belongs in modules/.
{
  lib,
  pkgs,
  self,
  ...
}:
let
  # What the dev VM's wrappers run for Google registries. gcloud's helper for
  # external tools reports the token *and* its expiry — the call kubectl's GKE
  # plugin makes — and `--min-expiry` refreshes one with under half an hour
  # left, so gcloud runs at most twice an hour and never hands over a token
  # about to die. Impersonation is honoured here like everywhere in gcloud
  # (PLAN.md backlog, the registry-only service account). Prompts off, so a
  # survey or an update nag cannot hold a pull.
  gcloudRegistryCredential = pkgs.writeShellApplication {
    name = "gcloud-registry-credential";
    runtimeInputs = [
      pkgs.google-cloud-sdk
      pkgs.jq
    ];
    text = ''
      export CLOUDSDK_CORE_DISABLE_PROMPTS=1
      gcloud config config-helper --min-expiry=30m --format=json |
        jq -c '{Username: "oauth2accesstoken", Secret: .credential.access_token, ExpiresAt: .credential.token_expiry}'
    '';
  };
in
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

  # Local Linux VM (PLAN.md Phase 8): which guest this Mac runs, and what it
  # gives it.
  devvm = {
    enable = true;
    guest = self.nixosConfigurations.devvm;

    # 8 GiB: sized beside Docker Desktop's own VM and kept after its
    # retirement — Docker ran on 8 for years, so this moves when something
    # asks for more.
    memory = "8GiB";

    # One directory, at the identical path on both sides. Not ~ : this guest
    # also runs third-party images, and ~/.ssh, the cloud credentials and
    # 1Password's state have no business inside it.
    mount = "/Users/alexm/code-shared";

    # Registries this Mac answers for; the credential is resolved here and
    # never stored in the guest (D23). gcr.io is the one work uses today, and
    # an Artifact Registry host would take the same command.
    registryAuth."gcr.io" = lib.getExe gcloudRegistryCredential;
  };

  # Compat marker, set once at this host's first install and then left
  # alone; the other host keeps its own value when it's ported in.
  system.stateVersion = 7;
}
