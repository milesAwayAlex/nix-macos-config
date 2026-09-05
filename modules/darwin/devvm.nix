# Host half of the development VM: the instance YAML lima is created from, the
# per-machine builder identity, the registration that lets the nix daemon use
# the guest, and the tools that look into it.
#
# The guest is a product: one of the flake's `nixosConfigurations`, built and
# rebuilt on its own, and a Mac names the one it runs in `devvm.guest`. What the
# Mac declares is what only it knows — sizing, disks, the port, the shared
# directory, its own shims. Everything that has to agree with the guest — which
# roles to serve, the builder account, the state disk's name, where the
# kubeconfig appears — is read from that configuration and never restated.
#
# DEVVM.md is the operating manual: bootstrap order, day-to-day recipes, what
# each kind of change costs.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.devvm;
  guest = cfg.guest.config;
  roles = guest.devvm or (throw "devvm.guest is not built with this flake's nixosModules.devvm");
  containers = roles.containers.enable || roles.cluster.enable;

  # The lima instance, and with it the ssh alias and the paths under ~/.lima;
  # the justfile and DEVVM.md use the same literal. The flake attribute is the
  # guest's own hostname, which is how nixos-rebuild finds it.
  name = "devvm";

  # Read from the guest, never restated: the two halves have to agree on where
  # the key goes and there is no reason for two literals.
  guestSsh = "${roles.stateDir}/ssh";

  keyFile = "/etc/nix/devvm_ed25519";
  knownHosts = "/etc/nix/devvm_known_hosts";
  # Where lima puts the guest's kubeconfig while the VM runs; `{{.Dir}}` below
  # is lima's own spelling of the same directory.
  kubeconfig = "$HOME/.lima/${name}/copied-from-guest/kubeconfig.yaml";

  limaYaml = (pkgs.formats.yaml { }).generate "lima-${name}.yaml" (
    {
      # Apple Virtualization rather than qemu: virtiofs instead of 9p, and no
      # emulation layer to pay for on aarch64 hosting aarch64.
      vmType = "vz";
      arch = "aarch64";

      # Seed only. lima reads `images` when it *creates* the instance and never
      # again; the first `nixos-rebuild` inside the guest replaces the entire
      # system, so the version here fixes what we boot once, not what we run.
      # Digest is upstream's own, from nixos-lima's nixos.yaml at v0.2.1 (D5);
      # bumping the flake input does not move it.
      images = [
        {
          location = "https://github.com/nixos-lima/nixos-lima/releases/download/v0.2.1/nixos-lima-v0.2.1-aarch64.qcow2";
          arch = "aarch64";
          digest = "sha512:748c723b69dbdec40a9acaf78cc9070ae784dcb64b0856ab906efdac822d9abcc65565b8f8dfa4cf8b49cc6c12c372072e83bb5ed9247330a7c22675d9e141ce";
        }
      ];

      inherit (cfg) cpus memory disk;
      ssh.localPort = cfg.sshPort;

      # lima's own containerd provisioning is for its stock images and would
      # install a second one; the guest declares whichever it needs.
      containerd = {
        system = false;
        user = false;
      };

      # Stop the guest agent intercepting the host's DHCP traffic — a
      # NixOS-only failure, nixos-lima issue #50.
      portForwards = [
        {
          proto = "udp";
          guestPort = 68;
          guestIP = "0.0.0.0";
          ignore = true;
        }
      ];

      # Empty unless this Mac shares a directory: a builder needs nothing from
      # the host filesystem. `mountPoint` is left implicit, which means the
      # guest path equals the host path — the identity that makes `-v $PWD:/app`
      # resolve to the same directory on both sides.
      mounts = lib.optional (cfg.mount != null) {
        location = cfg.mount;
        writable = true;
      };

      additionalDisks = lib.optional (roles.stateDisk != null) {
        name = roles.stateDisk;
        # Formatting is the guest's job: lima's own disk script never runs on a
        # NixOS guest.
        format = false;
      };
    }
    // lib.optionalAttrs roles.cluster.enable {
      # The guest publishes the kubeconfig only once k3s is up, and copyToHost
      # fails on a file that is not there yet.
      probes = [
        {
          description = "the guest's kubeconfig to exist";
          script = ''
            #!/bin/bash
            set -eux -o pipefail
            # The seed has no such unit and will never produce the file, and
            # lima retries a failing probe 200 times.
            [ -e /etc/systemd/system/devvm-kubeconfig.service ] || exit 0
            timeout 120s bash -c "until test -f ${roles.cluster.kubeconfig}; do sleep 3; done"
          '';
          hint = "k3s has not come up; check `limactl shell ${name} journalctl -u k3s`.";
        }
      ];
      copyToHost = [
        {
          guest = roles.cluster.kubeconfig;
          host = "{{.Dir}}/copied-from-guest/kubeconfig.yaml";
          # A stopped VM should make kubectl fail immediately rather than hang
          # on a dead 6443.
          deleteOnStop = true;
        }
      ];
    }
  );

  # Everything that runs in the guest runs through `limactl shell`: nerdctl has
  # no darwin build.
  #
  # Working directory: lima's own rule is `cd $PWD || cd ~`, so a build started
  # outside the shared directory would quietly run against the guest user's
  # home. `--workdir` makes it `cd || exit 1`. Under the mount the path is the
  # same on both sides, which is what makes `-v $PWD:/app` land where it should;
  # anywhere else the wrapper runs from /var/empty — NixOS keeps it empty, 0555
  # and immutable — so a relative path fails loudly while `ps`, `logs` and
  # `pull` work from wherever you are.
  #
  # Environment: forwarded, minus lima's own block list, because compose reads
  # `''${VAR}` from it. The locale variables stay behind on top of that — the
  # guest has its own, and a locale its glibc lacks makes every bash on the way
  # to nerdctl print a warning.
  shim =
    bin: target:
    pkgs.writeShellScriptBin bin ''
      export LIMA_SHELLENV_BLOCK="+LC_*,LANG,LANGUAGE"
      workdir=/var/empty
      ${lib.optionalString (cfg.mount != null) ''
        case "$PWD" in ${cfg.mount} | ${cfg.mount}/*) workdir="$PWD" ;; esac
      ''}
      exec ${pkgs.lima}/bin/limactl shell --preserve-env --workdir "$workdir" ${name} ${target} "$@"
    '';

  devvm-status = pkgs.writeShellApplication {
    name = "devvm-status";
    runtimeInputs = [
      pkgs.lima
      pkgs.kubectl
      pkgs.openssh
    ];
    text = ''
      name=${name}
      kubeconfig="${kubeconfig}"

      echo "── instance"
      if ! limactl list --format '{{.Name}}' 2>/dev/null | grep -qx "$name"; then
        echo "   $name: does not exist — \`just devvm-up\`"
        exit 0
      fi
      limactl list "$name" --format \
        '   {{.Name}}  {{.Status}}  {{.Arch}}  {{.CPUs}} cpu  {{.Memory}}  ssh :{{.SSHLocalPort}}'
      status=$(limactl list "$name" --format '{{.Status}}')

      ${lib.optionalString roles.builder.enable ''
        echo "── builder"
        if [ -f ${keyFile} ]; then
          echo "   key      ${keyFile}"
        else
          echo "   key      MISSING — \`just switch\` generates it"
        fi
        if [ -f ${knownHosts} ] && grep -q "^$name " ${knownHosts} 2>/dev/null; then
          echo "   host key pinned in ${knownHosts}"
        else
          echo "   host key NOT pinned — \`just devvm-adopt\`"
        fi
        echo "   verify   sudo nix store info --store ssh-ng://$name"
      ''}

      if [ "$status" != "Running" ]; then
        echo "── cluster/containerd: instance is $status"
        exit 0
      fi

      ${lib.optionalString roles.cluster.enable ''
        echo "── cluster"
        if [ -f "$kubeconfig" ]; then
          if KUBECONFIG="$kubeconfig" kubectl version --request-timeout=5s >/dev/null 2>&1; then
            KUBECONFIG="$kubeconfig" kubectl get nodes \
              --no-headers -o 'custom-columns=:.metadata.name,:.status.conditions[-1].type' 2>/dev/null |
              sed 's/^/   node     /'
            printf '   pods     '
            KUBECONFIG="$kubeconfig" kubectl get pods -A --no-headers 2>/dev/null |
              awk '{c[$4]++} END {for (s in c) printf "%s=%s ", s, c[s]; print ""}'
          else
            echo "   api      unreachable"
          fi
          echo "   context  ${guest.networking.hostName}"
        else
          echo "   kubeconfig not copied yet"
        fi
      ''}

      ${lib.optionalString containers ''
        echo "── containerd"
        # Single quotes on purpose: this expands in the guest, not here.
        # shellcheck disable=SC2016
        limactl shell "$name" sh -c '
          printf "   socket   %s\n" "$(sed -n "s/^address *= *\"unix:\/\/\(.*\)\"/\1/p" /etc/nerdctl/nerdctl.toml)"
          printf "   ns       %s\n" "$(sed -n "s/^namespace *= *\"\(.*\)\"/\1/p" /etc/nerdctl/nerdctl.toml)"
          printf "   images   %s\n" "$(nerdctl images -q 2>/dev/null | wc -l | tr -d " ")"
          printf "   running  %s\n" "$(nerdctl ps -q 2>/dev/null | wc -l | tr -d " ")"
          df -h / | awk "NR==2 {printf \"   disk     %s used of %s (%s)\n\", \$3, \$2, \$5}"
        ' 2>/dev/null || echo "   unreachable"
      ''}
    '';
  };

  # Idempotent, and the only step that is not declarative — by necessity: the
  # host's key is generated per machine and the guest's is generated per VM, so
  # neither can be known when this is built. Runs as the user, because limactl
  # refuses root; the one write into /etc/nix goes through sudo.
  devvm-adopt = pkgs.writeShellApplication {
    name = "devvm-adopt";
    runtimeInputs = [
      pkgs.lima
      pkgs.openssh
    ];
    text = ''
      name=${name}

      # 1. The guest's host key first, because it doubles as the readiness
      #    check: it exists only once the guest runs this configuration with the
      #    state disk mounted, so a premature adopt fails here rather than
      #    writing a key under a mountpoint that is not one yet. Read through
      #    `limactl shell` rather than scanned off the port: same trust window
      #    either way — lima's own ssh sets StrictHostKeyChecking=no — but one
      #    mechanism instead of two, and it yields the key already in the form
      #    a HostKeyAlias entry needs. Upstream's linux-builder can pin this at
      #    build time only because it ships one committed identity for every
      #    builder on earth.
      if ! hostkey=$(limactl shell "$name" sudo cat ${guestSsh}/ssh_host_ed25519_key.pub); then
        echo "no host key under ${guestSsh}: the guest is not running the devvm" \
          "configuration yet, or sshd started before the state disk mounted" \
          "(DEVVM.md, When it breaks)" >&2
        exit 1
      fi
      hostkey=$(echo "$hostkey" | cut -d' ' -f1-2)

      # 2. The host's public half into the guest, where sshd reads it from the
      #    state disk rather than from a generation — so it outlives rebuilds.
      #    World-readable, like NixOS's own /etc/ssh/authorized_keys.d: sshd
      #    opens the file *as the account*, so root-only modes lock it out.
      pub=$(cat ${keyFile}.pub)
      limactl shell "$name" sudo install -d -m 0755 ${guestSsh}/authorized_keys.d
      echo "$pub" |
        limactl shell "$name" sudo tee ${guestSsh}/authorized_keys.d/${roles.builder.user} >/dev/null
      limactl shell "$name" sudo chmod 0644 ${guestSsh}/authorized_keys.d/${roles.builder.user}
      echo "pushed $(echo "$pub" | cut -d' ' -f3) to ${roles.builder.user}@$name"

      # 3. Pin it. The file is world-readable, so only the write needs root.
      if [ -f ${knownHosts} ] && grep -qxF "$name $hostkey" ${knownHosts}; then
        echo "host key already pinned, unchanged"
      else
        tmp=$(mktemp)
        { grep -v "^$name " ${knownHosts} 2>/dev/null || true; echo "$name $hostkey"; } > "$tmp"
        sudo ${pkgs.coreutils}/bin/install -m 0644 "$tmp" ${knownHosts}
        rm -f "$tmp"
        echo "pinned host key for $name"
      fi
    '';
  };

  # Idempotent: the disk and the instance are created only when absent. Names
  # and sizes come from the configuration, so the justfile restates none.
  devvm-up = pkgs.writeShellApplication {
    name = "devvm-up";
    runtimeInputs = [
      pkgs.lima
      pkgs.gawk
      pkgs.gnugrep
    ];
    text = ''
      ${lib.optionalString (roles.stateDisk != null) ''
        if ! limactl disk ls | awk 'NR>1 {print $1}' | grep -qx ${roles.stateDisk}; then
          limactl disk create ${roles.stateDisk} --size ${cfg.stateDiskSize}
        fi
      ''}
      if ! limactl list -q | grep -qx ${name}; then
        limactl create --name ${name} --yes ${limaYaml}
      fi
      limactl start ${name}
    '';
  };
in
{
  options.devvm = {
    enable = lib.mkEnableOption "the local Linux development VM";

    guest = lib.mkOption {
      type = lib.types.raw;
      description = ''
        The NixOS configuration this VM runs: one of the flake's
        `nixosConfigurations`, built with `nixosModules.devvm`. The roles it
        enables decide what is set up here, and its hostname is the attribute
        `devvm-rebuild` deploys.
      '';
    };

    dockerShims = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Put `docker` and `docker-compose` on PATH as wrappers onto the guest's
        nerdctl, when the guest has one. They land in /run/current-system/sw/bin,
        ahead of the /usr/local/bin copies a manual Docker install leaves
        behind, and would shadow them.
      '';
    };

    # What this Mac gives the VM. lima reads these at instance creation into
    # its own copy of the template; DEVVM.md has the re-sync.
    cpus = lib.mkOption {
      type = lib.types.ints.positive;
      default = 6;
    };
    memory = lib.mkOption {
      type = lib.types.str;
      default = "12GiB";
    };
    disk = lib.mkOption {
      type = lib.types.str;
      default = "60GiB";
      description = "The OS disk. Disposable: every rebuild rewrites it.";
    };
    stateDiskSize = lib.mkOption {
      type = lib.types.str;
      default = "40GiB";
      description = "Size of the volume the guest's `devvm.stateDisk` names; `devvm-up` creates it.";
    };
    sshPort = lib.mkOption {
      type = lib.types.port;
      default = 60022;
      description = ''
        Pinned rather than left to lima's free-port pick, because the
        `nix.buildMachines` entry has to name a port at build time.
      '';
    };
    mount = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/Users/alexm/code-shared";
      description = ''
        One host directory, shared writable at the identical path so that
        `-v $PWD:/app` resolves the same on both sides. Null — the default,
        and right for a builder-only guest — shares nothing.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = [
          pkgs.lima
          # Deploys a guest change from here: the Mac evaluates, the guest builds
          # and activates its own system over lima's ssh. The builder role is not
          # involved, so a guest without it deploys the same way.
          pkgs.nixos-rebuild
          devvm-up
          devvm-status
        ]
        ++ lib.optional roles.builder.enable devvm-adopt
        ++ lib.optionals containers (
          [ (shim "nerdctl" "nerdctl") ]
          ++ lib.optionals cfg.dockerShims [
            (shim "docker" "nerdctl")
            (shim "docker-compose" "nerdctl compose")
          ]
        );

        # The instance YAML at a stable path, for humans; `devvm-up` hands lima the
        # store path directly. lima copies the template into ~/.lima/<name>/ at
        # creation and reads that copy on every start, so a change here reaches an
        # existing instance only by copying it over (DEVVM.md); the image and the
        # disk sizes are honoured at creation only.
        environment.etc."devvm/lima.yaml".source = limaYaml;
      }

      (lib.mkIf roles.cluster.enable {
        # kubectl, k9s and kubectx read a colon-separated list and merge it. The
        # Mac's own file stays first, so gcloud keeps writing there and nothing
        # is ever merged into it. The guest's context appears under the guest's
        # name while the VM runs and vanishes with it: kubectl skips a missing
        # file, and fails fast if the current context lived in it.
        environment.variables.KUBECONFIG = "$HOME/.kube/config:${kubeconfig}";
      })

      (lib.mkIf roles.builder.enable {
        # Per-machine builder identity: generated here on first switch, 0600 and
        # root-owned, and never in the repo or the store. The nix *daemon* is the
        # ssh client, running as root, so nothing in ~/.ssh is visible to it and
        # the key has to live somewhere root reads.
        system.activationScripts.postActivation.text = ''
          if [ ! -f ${keyFile} ]; then
            echo "generating devvm builder key"
            install -d -m 0755 /etc/nix
            ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" -q \
              -C "devvm builder on $(hostname -s)" -f ${keyFile}
            chmod 0600 ${keyFile}
          fi
        '';

        # HostKeyAlias, because known_hosts is keyed on host:port and every VM ever
        # run on this machine lives somewhere on localhost. StrictHostKeyChecking
        # yes, because the point of pinning is that an unknown key is a failure and
        # not a prompt no daemon can answer.
        environment.etc."ssh/ssh_config.d/101-devvm.conf".text = ''
          Host ${name}
            User ${roles.builder.user}
            Hostname 127.0.0.1
            Port ${toString cfg.sshPort}
            IdentityFile ${keyFile}
            IdentitiesOnly yes
            HostKeyAlias ${name}
            UserKnownHostsFile ${knownHosts}
            StrictHostKeyChecking yes
        '';

        # Defaults to false, and without it `buildMachines` is silently ignored
        # with nothing but a warning.
        nix.distributedBuilds = true;

        nix.buildMachines = [
          {
            hostName = name;
            sshUser = roles.builder.user;
            sshKey = keyFile;
            systems = [ guest.nixpkgs.hostPlatform.system ];
            # publicHostKey is deliberately unset: it would have to be known at
            # build time, and this guest generates its own. ${knownHosts} carries
            # the pin instead (D22).
            maxJobs = cfg.cpus;
            speedFactor = 1;
            protocol = "ssh-ng";
            supportedFeatures = [
              "benchmark"
              "big-parallel"
            ];
          }
        ];

        # So the builder pulls dependencies from the cache itself instead of the Mac
        # pushing them through the ssh pipe.
        nix.settings.builders-use-substitutes = true;
      })
    ]
  );
}
