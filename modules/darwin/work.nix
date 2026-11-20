# The employer's machine, whichever laptop that is: the tools its platform
# needs, the services its code expects, the password manager and the VM.
# Every work host imports it and states in hosts/<name>.nix only what that
# laptop alone knows — its user, its Homebrew history, its state versions
# (D25). The home half of the same split is ../home/work.nix.
{
  config,
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

  # The CA bundle the employer's endpoint scanner builds for nix and keeps
  # current: the stock roots, the machine's, and its own.
  scannerCaBundle = "/Library/Application Support/AikidoSecurity/EndpointProtection/run/endpoint-protection-nix-combined-ca.pem";
  # What the nix daemon is pointed at instead of either bundle by name: a
  # link, aimed at every switch (below).
  buildCaBundle = "/etc/nix/build-ca-certificates.crt";
in
{
  imports = [
    # Development services the work code expects at their default ports (D24);
    # `personal` runs none.
    ./postgresql.nix
    ./redis.nix
  ];

  # The password manager is per host (D19): its cask and its agent socket
  # (../home/work.nix) sit together; the browser extension is a hand install
  # (BOOTSTRAP.md). 1Password's cask verifies the real bundle for browser
  # integration and system auth.
  homebrew.casks = [ "1password" ];

  # Employer-coupled configuration, kept together: the tools, and the licence
  # exception one of them needs. `op` is unfree, and with
  # `useGlobalPkgs = true` home-manager evaluates against nix-darwin's
  # nixpkgs — so the predicate has to be set from this layer even though the
  # package is declared in a home module (D18).
  home-manager.sharedModules = [
    ../home/work.nix
    # GKE and its tooling: used on the employer's platform and nowhere else,
    # so they ride with the work hosts rather than the shared set.
    ../home/gcloud.nix
    ../home/k8s.nix
  ];
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      # nixpkgs extracts AgileBits' own signed `op` from their pkg and leaves
      # it unstripped, so the desktop app still verifies the binary. The cask
      # is not self-updating, which is what rules it out under D16.
      "1password-cli"
    ];

  # `pkgs.carman`: the memory client ../home/work.nix wires into Claude Code
  # (D33). Set here for the reason the predicate is — with `useGlobalPkgs`
  # a home module has no `nixpkgs.*` to add an overlay to.
  nixpkgs.overlays = [ self.inputs.carman.overlays.default ];

  # The endpoint scanner re-signs TLS to the package hosts — Go's proxy,
  # GitHub, npm, crates.io, PyPI — under a root of its own. Its nix rule puts
  # `ssl-cert-file` in nix.conf, which covers nix's own downloads; a
  # fixed-output build is handed NIX_SSL_CERT_FILE from the daemon's
  # *environment* instead, where nix-darwin puts the stock bundle, so every
  # fetcher that verifies — Go modules, npm and cargo vendoring, git — fails
  # on an unknown authority (D32). The daemon gets the scanner's bundle, then,
  # and through a link rather than by name: the same variable decides the
  # daemon's own downloads wherever nix.conf does not, and a path that is not
  # there fails those outright, substitution included. Each switch aims the
  # link at the scanner's bundle when it is readable and at the bundle
  # nix-darwin would have used when it is not, so a laptop the scanner has
  # not reached behaves as it did. The daemon alone: shells have the
  # scanner's own exports (D10).
  launchd.daemons.nix-daemon.serviceConfig.EnvironmentVariables.NIX_SSL_CERT_FILE = buildCaBundle;
  system.activationScripts.preActivation.text = ''
    install -d -m 0755 /etc/nix
    if [ -r ${lib.escapeShellArg scannerCaBundle} ]; then
      ln -sfn ${lib.escapeShellArg scannerCaBundle} ${buildCaBundle}
    else
      ln -sfn ${config.environment.variables.NIX_SSL_CERT_FILE} ${buildCaBundle}
    fi
  '';

  # Local Linux VM (PLAN.md Phase 8): which guest a work host runs, and what
  # it gives it.
  devvm = {
    enable = true;
    guest = self.nixosConfigurations.devvm;

    # 8 GiB: sized beside Docker Desktop's own VM and kept after its
    # retirement — Docker ran on 8 for years, so this moves when something
    # asks for more.
    memory = "8GiB";

    # The cluster's images outgrew the default 40: a sparse file, so the
    # room costs nothing until used. Read at creation; an existing disk is
    # grown by hand (DEVVM.md, What a change costs).
    stateDiskSize = "128GiB";

    # The cluster runs agents on a schedule, at night among other times, and
    # a sleeping Mac freezes the VM under them (D37). The work hosts only.
    keepAwake = true;

    # One directory, at the identical path on both sides. Not ~ : this guest
    # also runs third-party images, and ~/.ssh, the cloud credentials and
    # 1Password's state have no business inside it.
    mount = "${config.users.users.${config.system.primaryUser}.home}/code-shared";

    # Registries this Mac answers for; the credential is resolved here and
    # never stored in the guest (D23). gcr.io is the one work uses today, and
    # an Artifact Registry host would take the same command.
    registryAuth."gcr.io" = lib.getExe gcloudRegistryCredential;
  };
}
