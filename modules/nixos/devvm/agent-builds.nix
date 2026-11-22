# Image builds for the cluster's agents (D40): a BuildKit daemon of their own,
# writing to its own containerd namespace and pushing to a registry on the
# node that the cluster pulls from. An agent's image can only be named
# localhost:5050/…, so it never takes a tag the cluster runs, and every store
# it fills has a cap.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.devvm.agentBuilds;
  stateDir = config.devvm.stateDir;
  containerdSocket = "/run/k3s/containerd/containerd.sock";
  namespace = "agents";
  # nerdctl's own convention for a namespace's daemon, so
  # `nerdctl --namespace agents build` finds it too.
  socketDir = "/run/buildkit-${namespace}";
  registry = "localhost:${toString cfg.registryPort}";
  registryDir = "${stateDir}/registry";
  registryCapMiB = 15 * 1024;

  buildkitdConfig = (pkgs.formats.toml { }).generate "buildkitd-agents.toml" {
    # On the state disk, where the layers are: minFreeSpace is measured on
    # the filesystem that holds this directory.
    root = "${stateDir}/buildkit-${namespace}";
    grpc = {
      address = [ "unix://${socketDir}/buildkitd.sock" ];
      inherit (cfg) gid;
    };
    worker.oci.enabled = false;
    worker.containerd = {
      enabled = true;
      address = containerdSocket;
      inherit namespace;
      gc = true;
      gcpolicy = [
        {
          all = true;
          reservedSpace = "1GB";
          maxUsedSpace = "10GB";
          minFreeSpace = "15GB";
        }
      ];
    };
    registry.${registry}.http = true;
  };
in
{
  options.devvm.agentBuilds = {
    enable = lib.mkEnableOption "a BuildKit daemon and registry for the cluster's agents";
    gid = lib.mkOption {
      type = lib.types.int;
      default = 10100;
      description = "Group that owns the daemon's socket; a pod joins it as a supplemental group.";
    };
    registryPort = lib.mkOption {
      type = lib.types.port;
      default = 5050;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.devvm.cluster.enable;
        message = "devvm.agentBuilds needs devvm.cluster";
      }
    ];

    users.groups.agent-builds.gid = cfg.gid;

    systemd.services.buildkitd-agents = {
      description = "BuildKit daemon for the cluster's agents";
      wantedBy = [ "multi-user.target" ];
      # As buildkitd's: Requires so a rebuild starts k3s first.
      requires = [ "k3s.service" ];
      after = [ "k3s.service" ];
      unitConfig.RequiresMountsFor = stateDir;
      serviceConfig = {
        Type = "notify";
        ExecStart = "${pkgs.buildkit}/bin/buildkitd --config ${buildkitdConfig}";
        Restart = "always";
        RestartSec = "5s";
      };
    };

    # Loopback only: the daemons push here, k3s's containerd pulls from here,
    # both on the node. containerd and BuildKit speak plain HTTP to localhost.
    services.dockerRegistry = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = cfg.registryPort;
      storagePath = registryDir;
      enableDelete = true;
    };
    systemd.services.docker-registry.unitConfig.RequiresMountsFor = stateDir;

    # The caps the daemon's own GC does not cover: image records in the
    # agents namespace (the registry is where builds are meant to go), and
    # the registry itself — tags not pushed for a week, then older ones
    # while it is over its cap.
    systemd.services.agent-builds-prune = {
      description = "Prune what the agents' builds keep";
      startAt = "daily";
      after = [ "k3s.service" ];
      serviceConfig.Type = "oneshot";
      path = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.nerdctl
        config.services.dockerRegistry.package
      ];
      script = ''
        nerdctl --address ${containerdSocket} --namespace ${namespace} image prune --all --force

        tags=${registryDir}/docker/registry/v2/repositories
        prune() {
          if [ -d "$tags" ]; then
            find "$tags" -path '*/_manifests/tags/*/current/link' "$@" -printf '%h\n' |
              xargs -r -n1 dirname | xargs -r rm -rf
          fi
          registry garbage-collect --delete-untagged ${config.services.dockerRegistry.configFile}
        }
        systemctl stop docker-registry
        trap 'systemctl start docker-registry' EXIT
        prune -mtime +7
        for age in "-mtime +2" "-mtime +0" "-mmin +60"; do
          [ "$(du -sm ${registryDir} | cut -f1)" -le ${toString registryCapMiB} ] && break
          # shellcheck disable=SC2086
          prune $age
        done
        echo "registry: $(du -sh ${registryDir} | cut -f1)"
      '';
    };
  };
}
