# The development VM's guest OS: an `aarch64-linux` remote builder, a
# single-node k3s cluster, and the container runtime behind a docker-compatible
# CLI. lima owns the outer shape only — vmType, cpus, memory, disks, mounts,
# forwarded ports — and everything from the bootloader up is declared here,
# moved by `nixos-rebuild` run inside the guest. The flake exports the role
# sets a Mac can pick from; this module is what they share.
#
# The three roles are separate enables because they need not travel together: a
# machine that wants only the builder gets sshd and nothing else, and in
# particular gets no host mount at all — nix ships sources into the store over
# ssh, so a builder-only guest sees none of the host filesystem.
{
  config,
  lib,
  modulesPath,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.devvm;
  containers = cfg.containers.enable || cfg.cluster.enable;

  # With the cluster on, k3s's embedded containerd is the only daemon and the
  # only content store, so an image built here *is* the image the cluster runs.
  # Nothing below writes either value as a literal.
  socket =
    if cfg.cluster.enable then
      "/run/k3s/containerd/containerd.sock"
    else
      "/run/containerd/containerd.sock";
  namespace = if cfg.cluster.enable then "k8s.io" else "default";

  # lima labels an `additionalDisks` volume `lima-<name>`; it also mounts it,
  # but only from a boot script that its own guest images run and a NixOS guest
  # never sees, so the mount and the one-time format are ours (below).
  stateDir = cfg.stateDir;
  stateLabel = "lima-${toString cfg.stateDisk}";

  # nerdctl is rootful here — root's socket, root's data root, CNI as root —
  # and the shell `limactl shell` opens is the lima user's, so every call goes
  # through sudo. Wrapped rather than granted: a group on the socket would not
  # cover the rest. `-E` keeps the environment the Mac side forwarded, which is
  # what compose's `''${VAR}` interpolation reads and where the registry
  # credentials arrive; the wheel rule is `ALL`, so sudo allows it. Also under
  # the name the work repos call it by — a wrapper rather than a shell alias,
  # because compose files and repo scripts are not shells.
  nerdctl =
    bin:
    pkgs.writeShellScriptBin bin ''
      export DOCKER_CONFIG=${dockerConfig}
      [ "$(id -u)" = 0 ] || exec /run/wrappers/bin/sudo -E ${pkgs.nerdctl}/bin/nerdctl "$@"
      exec ${pkgs.nerdctl}/bin/nerdctl "$@"
    '';

  # nerdctl's credential store is the environment. The Mac's wrappers resolve
  # credentials for the hosts they are configured to answer for and send them
  # along in one variable — a JSON object keyed by registry host — and this
  # helper hands them back per request, so nothing is stored in the guest and a
  # token lives exactly as long as the call that carried it. `store` is
  # refused: a login has nowhere to go here, by design (D23). The config that
  # names the helper lives in the store, read-only, which nerdctl and buildkit
  # both accept. The not-found reply is the protocol's literal sentinel; any
  # other text is taken for an error, and nerdctl has been seen to hang on one.
  dockerConfig = pkgs.writeTextDir "config.json" (builtins.toJSON { credsStore = "devvm"; });
  credentialHelper = pkgs.writeShellApplication {
    name = "docker-credential-devvm";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      auth=''${${cfg.containers.registryAuthEnv}:-"{}"}
      case "''${1:-}" in
        get)
          # One registry is asked for under several spellings — with a scheme,
          # with :443, with a path — so reduce them to the host.
          host=$(sed -E 's#^https?://##; s#/.*$##; s#:443$##')
          if cred=$(jq -ce --arg h "$host" '.[$h]' <<<"$auth" 2>/dev/null); then
            printf '%s\n' "$cred"
          else
            echo "credentials not found in native keychain"
            exit 1
          fi
          ;;
        list) jq -c 'map_values(.Username)' <<<"$auth" ;;
        *)
          echo "docker-credential-devvm: registry logins live on the Mac (devvm.registryAuth); nothing is stored here" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  options.devvm = {
    builder = {
      enable = lib.mkEnableOption "the aarch64-linux remote builder role" // {
        default = true;
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = "builder";
        description = ''
          Guest account the host's nix daemon connects as. Deliberately not the
          lima user, whose `authorized_keys` lima rewrites on every boot, and
          deliberately not root, which would add a shell nothing here needs.
        '';
      };
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/devvm";
      readOnly = true;
      description = ''
        Where the state disk is mounted. Read-only, and published rather than
        kept private because the host half needs the same path to put its
        public key in the right place.
      '';
    };

    containers = {
      enable = lib.mkEnableOption "containerd, nerdctl and buildkit";
      registryAuthEnv = lib.mkOption {
        type = lib.types.str;
        default = "DEVVM_REGISTRY_AUTH";
        readOnly = true;
        description = ''
          The variable in which the Mac's wrappers deliver registry credentials
          for one call: a JSON object keyed by registry host. Read-only and
          published because the host half has to send exactly this name.
        '';
      };
    };

    cluster = {
      enable = lib.mkEnableOption "a single-node k3s cluster (brings its own containerd)";
      kubeconfig = lib.mkOption {
        type = lib.types.str;
        default = "/run/devvm/kubeconfig.yaml";
        readOnly = true;
        description = ''
          The cluster's kubeconfig, published under this machine's name rather
          than k3s's `default`, world-readable. Read-only and published because
          the host half copies it out from here.
        '';
      };
    };

    # The guest has to find the volume by lima's name, so the guest owns the
    # name; the darwin module reads it to attach the disk rather than restating
    # it.
    stateDisk = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "devvm-state";
      description = ''
        Name of the lima volume holding the state that should outlive the OS
        disk: the ssh host key and the cluster's data. The guest formats and
        mounts it by this name; the host attaches a volume with the same one.
        Null keeps both on the root filesystem, where they survive every reboot
        and rebuild but not a `limactl delete`.
      '';
    };
  };

  config = lib.mkMerge [
    {
      # ---- the lima guest contract ----
      services.lima.enable = true;

      # Mandatory, not stylistic: lima creates its user imperatively on every
      # boot, and a rebuild with `mutableUsers = false` deletes that user and
      # the `limactl shell` access along with it.
      users.mutableUsers = true;

      # The host mount is lima-init's, from the seed's user-data, and cannot be
      # declared in `fileSystems`: the virtiofs tag is lima's sha256 over
      # location, a NUL byte and mount point, and a Nix string cannot hold the
      # NUL. lima-init mounts it by appending to /etc/fstab, a file NixOS
      # generates — every switch compares the live file with the new one,
      # unmounts what the new one lacks and puts the symlink back, so the share
      # lived from boot until the first rebuild. Activation runs between that
      # unmount and the unit starts, which is where this fits: mount whatever
      # user-data lists and is not mounted. At boot the cidata volume is not
      # mounted yet and lima-init does the work. A mount that fails fails the
      # switch out loud. The parse is lima-init's own, so the two read one
      # file the same way.
      system.activationScripts.devvm-mounts.text = ''
        userData=/mnt/lima-cidata/user-data
        if [ -r "$userData" ]; then
          ${lib.getExe pkgs.gawk} '
            /^mounts:/ { flag = 1; next }
            /^[^:]*:/ || /^ *$/ { flag = 0 }
            flag { sub(/^ *- \[/, ""); sub(/"?\] *$/, ""); gsub("\"?, \"?", "\t"); print }
          ' "$userData" |
          while read -r tag dir type opts _; do
            ${pkgs.util-linux}/bin/mountpoint -q "$dir" ||
              ${pkgs.util-linux}/bin/mount -t "$type" -o "$opts" "$tag" "$dir"
          done
        fi
      '';

      # Disk layout of the seed image, declared rather than inherited: the
      # first rebuild rewrites the bootloader config, and it has to describe
      # the disk actually underneath it.
      boot = {
        kernelParams = [ "console=tty0" ];
        growPartition = true;
        loader.grub = {
          device = "nodev";
          efiSupport = true;
          efiInstallAsRemovable = true;
          # /boot is the seed's 249 MiB EFI partition, and GRUB copies the
          # kernel and initrd of every menu entry onto it: 90 MiB a pair, so
          # two fit, and an install holds the listed pairs and the new one at
          # once before it prunes. One entry, then — the third distinct kernel
          # would fail the switch with "No space left on device". Rollback does
          # not need the menu: `nixos-rebuild --rollback` re-installs the
          # previous generation, and nothing ever sees the menu here anyway.
          configurationLimit = 1;
        };
      };
      fileSystems."/boot" = {
        device = "/dev/vda1";
        fsType = "vfat";
      };
      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
        autoResize = true;
        options = [
          "noatime"
          "nodiratime"
          "discard"
        ];
      };

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      # D4 on the guest too: the store here grows with every rebuild and with
      # every builder job whose output the Mac has already copied back. The
      # reactive floor is sized for the 60 GiB OS disk, which holds the store
      # and little else — the cluster's images live on the state disk.
      nix.gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 14d";
      };
      nix.optimise.automatic = true;
      nix.settings.min-free = 5 * 1024 * 1024 * 1024; # 5 GiB
      nix.settings.max-free = 15 * 1024 * 1024 * 1024; # 15 GiB
      security.sudo.wheelNeedsPassword = false;
      environment.systemPackages = [ pkgs.gitMinimal ];
      system.stateVersion = "26.05";
    }

    # ---- state disk ----
    (lib.mkIf (cfg.stateDisk != null) {
      # lima attaches the volume raw. Formatting it is normally the job of
      # lima's own 05-lima-disks.sh, which a NixOS guest never runs, so do that
      # one step here to lima's convention — GPT, ext4, labelled lima-<name> —
      # reading the device name out of the seed rather than guessing at /dev/vdb.
      # The label is also the guard: a disk that has one is never touched, and a
      # device carrying any signature at all is refused rather than reformatted.
      systemd.services.devvm-state-disk = {
        description = "Format the lima state disk on first boot";
        unitConfig.RequiresMountsFor = "/mnt/lima-cidata";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [
          pkgs.util-linux
          pkgs.e2fsprogs
        ];
        script = ''
          set -eu
          if [ -b /dev/disk/by-label/${stateLabel} ]; then
            exit 0
          fi

          while read -r line; do export "$line"; done < /mnt/lima-cidata/lima.env
          get() { eval "printf '%s' \"\''${LIMA_CIDATA_DISK_$1_$2:-}\""; }

          i=0
          while [ "$i" -lt "''${LIMA_CIDATA_DISKS:-0}" ]; do
            if [ "$(get "$i" NAME)" = "${toString cfg.stateDisk}" ]; then
              dev="/dev/$(get "$i" DEVICE)"
              if blkid "$dev" >/dev/null 2>&1; then
                echo "$dev already carries a signature; refusing to format" >&2
                exit 1
              fi
              echo 'type=linux' | sfdisk --label gpt "$dev"
              udevadm settle
              mkfs.ext4 -L ${stateLabel} "''${dev}1"
              udevadm settle
              exit 0
            fi
            i=$((i + 1))
          done

          echo "lima reports no disk named ${toString cfg.stateDisk}" >&2
          exit 1
        '';
      };

      # `nofail` keeps the guest bootable, and reachable over the console,
      # without the disk. systemd then does not order the mount before
      # local-fs.target, so every unit that writes under it says so with
      # RequiresMountsFor and fails without the disk — otherwise sshd's key
      # generation wins the race and its key lands on the root filesystem,
      # hidden under the mount a second later.
      fileSystems.${stateDir} = {
        device = "/dev/disk/by-label/${stateLabel}";
        fsType = "ext4";
        options = [
          "nofail"
          "x-systemd.device-timeout=30s"
          "x-systemd.requires=devvm-state-disk.service"
        ];
      };
    })

    # ---- builder ----
    (lib.mkIf cfg.builder.enable {
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          PermitRootLogin = "no";
        };

        # On the state disk, so the guest's identity survives a rebuild and a
        # recreate, which keeps the host's first-use trust once per machine
        # rather than once per VM.
        hostKeys = [
          {
            type = "ed25519";
            path = "${stateDir}/ssh/ssh_host_ed25519_key";
          }
        ];

        # The host's public key is generated per machine at activation and so
        # can never be committed; it arrives at runtime and lands here. This
        # merges with the module's own /etc/ssh/authorized_keys.d/%u, which is
        # where lima writes its user's key — replacing that list would lock
        # `limactl shell` out of the machine.
        authorizedKeysFiles = [ "${stateDir}/ssh/authorized_keys.d/%u" ];
      };

      # Both the key and the authorized keys are under the state disk's mount.
      systemd.services.sshd-keygen.unitConfig.RequiresMountsFor = stateDir;
      systemd.services.sshd.unitConfig.RequiresMountsFor = stateDir;

      users.users.${cfg.builder.user} = {
        isNormalUser = true;
        description = "remote build account for the host's nix daemon";
      };

      # A trusted nix user can already ask the daemon to build anything, which
      # is the whole job; root would add reach it does not need.
      nix.settings.trusted-users = [ cfg.builder.user ];
    })

    # ---- containers ----
    (lib.mkIf containers {
      environment.systemPackages = [
        (nerdctl "nerdctl")
        (nerdctl "docker")
        credentialHelper
        pkgs.cri-tools
      ];

      # The credentials arrive over the SSH session, sent by the Mac's wrappers
      # with SendEnv; sshd drops what it was not told to accept. lima's own
      # environment forwarding travels on the command line instead, which is
      # exactly why this variable does not go that way.
      services.openssh.settings.AcceptEnv = [ cfg.containers.registryAuthEnv ];

      # One place the socket and the namespace are written down for every
      # client. nerdctl's own documentation uses exactly this pair for k3s.
      environment.etc."nerdctl/nerdctl.toml".text = ''
        address   = "unix://${socket}"
        namespace = "${namespace}"
      '';

      # crictl speaks CRI, so it reports what the kubelet sees rather than what
      # the content store holds — a different question, and the useful one when
      # a pod will not start.
      environment.etc."crictl.yaml".text = ''
        runtime-endpoint: unix://${socket}
        image-endpoint: unix://${socket}
      '';

      # `nerdctl build` needs buildkit, and buildkit has to be pointed at the
      # same containerd *and the same namespace*, or a built image lands where
      # the cluster cannot see it. nixpkgs has no module for it.
      systemd.services.buildkitd =
        let
          containerdUnit = if cfg.cluster.enable then "k3s.service" else "containerd.service";
        in
        {
          description = "BuildKit daemon, sharing containerd's content store";
          wantedBy = [ "multi-user.target" ];
          # Requires as well as After: activation starts stopped units one at a
          # time, each as its own job, and After alone orders nothing between
          # separate jobs — a rebuild that changed both units started buildkitd
          # before k3s and it died on a socket that did not exist yet. Requires
          # pulls the containerd unit into buildkitd's own start, where the
          # ordering holds.
          requires = [ containerdUnit ];
          after = [ containerdUnit ];
          serviceConfig = {
            Type = "notify";
            ExecStart = lib.concatStringsSep " " [
              "${pkgs.buildkit}/bin/buildkitd"
              "--oci-worker=false"
              "--containerd-worker=true"
              "--containerd-worker-addr=${socket}"
              "--containerd-worker-namespace=${namespace}"
            ];
            # For the case Requires does not cover: the containerd unit crashing
            # and restarting itself takes the socket away and brings it back.
            Restart = "always";
            RestartSec = "5s";
          };
        };

      # Only when nothing else brings one: k3s embeds its own.
      virtualisation.containerd.enable = !cfg.cluster.enable;
    })

    (lib.mkIf (containers && !cfg.cluster.enable && cfg.stateDisk != null) {
      virtualisation.containerd.settings.root = "${stateDir}/containerd";
      systemd.services.containerd.unitConfig.RequiresMountsFor = stateDir;
    })

    # ---- cluster ----
    (lib.mkIf cfg.cluster.enable {
      services.k3s = {
        enable = true;
        role = "server";

        # traefik exists to serve Ingress, and serving it means a LoadBalancer
        # service that klipper-lb satisfies by binding 80 and 443 on the node,
        # which lima then forwards to the Mac's localhost for as long as the VM
        # is up. Worth that only once something here actually deploys Ingress
        # manifests. metrics-server stays: it is what fills k9s's CPU and memory
        # columns. local-storage stays: it is the default StorageClass, so PVCs
        # bind instead of hanging. servicelb stays and creates nothing until
        # something asks for a LoadBalancer, which keeps turning traefik back on
        # a one-word edit.
        disable = [ "traefik" ];

        # k3s's own component images, pinned by the flake rather than by
        # whatever registry.k3s.io serves today, and imported into containerd
        # before the first pod is scheduled — so a fresh VM comes up with no
        # network at all. ~216 MiB, plus the unpacked copy.
        images = [ config.services.k3s.package.airgap-images ];

        extraFlags = [
          # The kubelet frees images it considers unused above the high
          # threshold, and it counts only CRI-managed containers as users — so
          # an image built here that no pod happens to be running is eligible.
          # This is the same content store nerdctl builds into (D23), so the
          # defaults of 85/80 are too eager to be left alone.
          "--kubelet-arg=image-gc-high-threshold=95"
          "--kubelet-arg=image-gc-low-threshold=90"
        ];
      };

      # k3s names its cluster, context and user `default`, and same-named
      # entries collide when the Mac merges the file with its own kubeconfig.
      # Published again under this machine's name for lima to copy out. Only the
      # four `: default` lines change; the credentials are base64 and cannot
      # end that way. k3s.yaml itself stays root's.
      systemd.services.devvm-kubeconfig = {
        description = "Publish the k3s kubeconfig under this host's name";
        wantedBy = [ "multi-user.target" ];
        after = [ "k3s.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          RuntimeDirectory = "devvm";
          # k3s writes the file once its API is up; a guest where that never
          # happens should fail this unit rather than hold it activating.
          TimeoutStartSec = "5min";
        };
        script = ''
          until [ -s /etc/rancher/k3s/k3s.yaml ]; do sleep 2; done
          sed 's/: default$/: ${config.networking.hostName}/' /etc/rancher/k3s/k3s.yaml > ${cfg.cluster.kubeconfig}.tmp
          chmod 0644 ${cfg.cluster.kubeconfig}.tmp
          mv ${cfg.cluster.kubeconfig}.tmp ${cfg.cluster.kubeconfig}
        '';
      };

      # A single-node cluster behind lima's NAT, reached only through forwarded
      # loopback ports. A host firewall here blocks pod and API traffic and
      # protects nothing that the Mac is not already protecting.
      networking.firewall.enable = false;
    })

    (lib.mkIf (cfg.cluster.enable && cfg.stateDisk != null) {
      # k3s keeps its containerd, its images and its sqlite datastore under one
      # directory, so the cluster follows the state disk with a single bind.
      # The source has to exist before local-fs.target mounts it, which is
      # earlier than tmpfiles runs.
      systemd.services.devvm-state-dirs = {
        description = "Create state directories on the lima state disk";
        unitConfig.RequiresMountsFor = stateDir;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = "install -d -m 0700 ${stateDir}/rancher";
      };
      fileSystems."/var/lib/rancher" = {
        device = "${stateDir}/rancher";
        fsType = "none";
        options = [
          "bind"
          "nofail"
          "x-systemd.requires=devvm-state-dirs.service"
        ];
        depends = [ stateDir ];
      };
      systemd.services.k3s.unitConfig.RequiresMountsFor = "/var/lib/rancher";
    })
  ];
}
