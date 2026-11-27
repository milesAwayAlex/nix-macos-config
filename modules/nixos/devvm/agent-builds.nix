# Image builds for the cluster's agents (D40, D45): a BuildKit daemon of their
# own, writing to its own containerd namespace and pushing to a registry on
# the node that the cluster pulls from. An agent's image can only be named
# localhost:5050/…, so it never takes a tag the cluster runs, and every store
# it fills has a cap. An owner's repositories take writes only with its key,
# and builds run on a network of their own, off the node's.
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
  # distribution listens here only, so every request passes nginx's checks.
  registrySocket = "/run/docker-registry/registry.sock";
  # One htpasswd file per owner, written from the Mac (devvm-registry-key).
  authDir = "${stateDir}/registry-auth";
  # Linux caps an interface name at 15 characters.
  buildBridge = "buildkit-agents";
  # The bridge's own address: the CNI gateway, and where the builds' resolver listens.
  buildGateway = lib.removeSuffix "0/24" cfg.buildSubnet + "1";
  # lima's resolver fails every AAAA query, which fails musl's whole lookup
  # (Alpine's apk); the builds have no IPv6, so AAAA is answered with nothing.
  buildsCorefile = pkgs.writeText "Corefile-agent-builds" ''
    .:53 {
        bind ${buildGateway}
        errors
        template IN AAAA . {
            rcode NOERROR
        }
        forward . 192.168.5.2
        cache 30
    }
  '';

  buildkitdConfig = (pkgs.formats.toml { }).generate "buildkitd-agents.toml" {
    # On the state disk, where the layers are: minFreeSpace is measured on
    # the filesystem that holds this directory.
    root = "${stateDir}/buildkit-${namespace}";
    history = {
      maxAge = "168h";
      maxEntries = 100;
    };
    grpc = {
      address = [ "unix://${socketDir}/buildkitd.sock" ];
      inherit (cfg) gid;
    };
    worker.oci.enabled = false;
    worker.containerd = {
      enabled = true;
      address = containerdSocket;
      inherit namespace;
      # A network per RUN step, on a bridge of its own; agent-builds-network
      # filters what it reaches.
      networkMode = "bridge";
      bridgeName = buildBridge;
      bridgeSubnet = cfg.buildSubnet;
      cniBinaryPath = "${pkgs.cni-plugins}/bin";
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
    dns.nameservers = [ buildGateway ];
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
    registryOwners = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[a-z0-9]+");
      default = [ ];
      description = "Owners whose repositories (NAME, NAME-*, NAME/*) take writes only with NAME's key.";
    };
    buildSubnet = lib.mkOption {
      type = lib.types.str;
      default = "10.89.0.0/24";
      description = "Addresses of the builds' RUN steps; not the pods' or the services'.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.devvm.cluster.enable;
        message = "devvm.agentBuilds needs devvm.cluster";
      }
      {
        assertion = builtins.match "([0-9]+\\.){3}0/24" cfg.buildSubnet != null;
        message = "devvm.agentBuilds.buildSubnet must be a /24 ending in .0/24";
      }
    ];

    users.groups.agent-builds.gid = cfg.gid;

    systemd.services.buildkitd-agents = {
      description = "BuildKit daemon for the cluster's agents";
      wantedBy = [ "multi-user.target" ];
      # As buildkitd's: Requires so a rebuild starts k3s first. No build
      # runs before its network is filtered.
      requires = [
        "k3s.service"
        "agent-builds-network.service"
      ];
      wants = [ "agent-builds-dns.service" ];
      after = [
        "k3s.service"
        "agent-builds-network.service"
        "agent-builds-dns.service"
      ];
      # The bridge plugin sets up masquerading with iptables.
      path = [ pkgs.iptables ];
      unitConfig.RequiresMountsFor = stateDir;
      serviceConfig = {
        Type = "notify";
        ExecStart = "${pkgs.buildkit}/bin/buildkitd --config ${buildkitdConfig}";
        Restart = "always";
        RestartSec = "5s";
      };
    };

    # A RUN step reaches the internet and its resolver on the gateway, nothing
    # else (D45). raw sees the address asked for, before a Service's is
    # translated; the interface, unlike a source address, cannot be forged.
    systemd.services.agent-builds-network = {
      description = "Keep the agents' builds off the node and private networks";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        pkgs.iproute2
        pkgs.iptables
      ];
      script = ''
        # The bridge exists before the first RUN step makes it, so the
        # resolver can listen on it from boot. CNI takes it as it finds it.
        ip link show ${buildBridge} >/dev/null 2>&1 || ip link add name ${buildBridge} type bridge
        ip addr replace ${buildGateway}/24 dev ${buildBridge}
        ip link set ${buildBridge} up

        iptables -w -t raw -N AGENT-BUILDS 2>/dev/null || iptables -w -t raw -F AGENT-BUILDS
        for proto in udp tcp; do
          iptables -w -t raw -A AGENT-BUILDS -d ${buildGateway} -p "$proto" --dport 53 -j RETURN
        done
        for net in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 \
          172.16.0.0/12 192.168.0.0/16 224.0.0.0/3; do
          iptables -w -t raw -A AGENT-BUILDS -d "$net" -j DROP
        done
        iptables -w -t raw -C PREROUTING -i ${buildBridge} -j AGENT-BUILDS 2>/dev/null ||
          iptables -w -t raw -I PREROUTING -i ${buildBridge} -j AGENT-BUILDS
        # No IPv6 at all: link-local would reach the node.
        ip6tables -w -t raw -C PREROUTING -i ${buildBridge} -j DROP 2>/dev/null ||
          ip6tables -w -t raw -I PREROUTING -i ${buildBridge} -j DROP
      '';
    };

    # The builds' resolver: lima's, but with AAAA answered empty.
    systemd.services.agent-builds-dns = {
      description = "DNS for the agents' builds";
      wantedBy = [ "multi-user.target" ];
      requires = [ "agent-builds-network.service" ];
      after = [ "agent-builds-network.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.coredns}/bin/coredns -conf ${buildsCorefile}";
        DynamicUser = true;
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        NoNewPrivileges = true;
        Restart = "always";
        RestartSec = "5s";
      };
    };

    # distribution on a socket only nginx can open; nginx on every address,
    # the pods' 10.42.0.1 among them. Writes to an owner's repositories take
    # its key (D45); everything else is open.
    services.dockerRegistry = {
      enable = true;
      storagePath = registryDir;
      enableDelete = true;
      extraConfig.http = {
        net = "unix";
        addr = registrySocket;
      };
    };
    systemd.services.docker-registry = {
      unitConfig.RequiresMountsFor = stateDir;
      serviceConfig = {
        RuntimeDirectory = "docker-registry";
        RuntimeDirectoryMode = "0750";
        UMask = "0007";
      };
    };
    users.users.nginx.extraGroups = [ "docker-registry" ];

    # Empty until a key is installed: an owner's repositories refuse writes.
    systemd.tmpfiles.rules = [
      "d ${authDir} 0750 root nginx -"
    ]
    ++ map (owner: "f ${authDir}/${owner}.htpasswd 0640 root nginx -") cfg.registryOwners;

    services.nginx = {
      enable = true;
      upstreams.registry.servers."unix:${registrySocket}" = { };
      # Writes go to the journal, with the user that made them.
      appendHttpConfig = ''
        map $request_method $registry_write {
          GET 0;
          HEAD 0;
          default 1;
        }
      '';
      virtualHosts.registry = {
        listen = [
          {
            addr = "0.0.0.0";
            port = cfg.registryPort;
          }
        ];
        # proxy_pass sends the request as it came: a decoded $uri could carry
        # a line break. Host keeps the port for distribution's upload URLs.
        extraConfig = ''
          access_log syslog:server=unix:/dev/log,nohostname,tag=registry_writes combined if=$registry_write;
          client_max_body_size 0;
          proxy_request_buffering off;
          proxy_buffering off;
          proxy_http_version 1.1;
          proxy_read_timeout 900s;
          proxy_send_timeout 900s;
          proxy_set_header Host $host:$server_port;
        '';
        locations = {
          # crane sends credentials only after a 401 here.
          "= /v2/".extraConfig = ''
            if ($http_authorization = "") {
              add_header WWW-Authenticate 'Basic realm="registry"' always;
              return 401;
            }
            proxy_pass http://registry;
          '';
          "/".extraConfig = ''
            proxy_pass http://registry;
          '';
        }
        // lib.listToAttrs (
          map (owner: {
            name = "~ ^/v2/${owner}(?:[-/][^/]+)*/(?:manifests|blobs|tags|referrers)/";
            value.extraConfig = ''
              limit_except GET HEAD {
                auth_basic "${owner}";
                auth_basic_user_file ${authDir}/${owner}.htpasswd;
              }
              proxy_pass http://registry;
            '';
          }) cfg.registryOwners
        );
      };
    };

    # The caps the daemon's own GC does not cover: image records in the
    # agents namespace (the registry is where builds are meant to go), and
    # the registry itself — tags not pushed for a week, then older ones
    # while it is over its cap. A tag a workload names is kept: the kubelet
    # frees images no pod is running, and pulls them back from here.
    systemd.services.agent-builds-prune = {
      description = "Prune what the agents' builds keep";
      startAt = "daily";
      after = [ "k3s.service" ];
      serviceConfig.Type = "oneshot";
      path = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.jq
        pkgs.nerdctl
        config.services.dockerRegistry.package
        config.services.k3s.package
      ];
      script = ''
        # No list of what workloads name, no pruning of the registry.
        set -o pipefail
        nerdctl --address ${containerdSocket} --namespace ${namespace} image prune --all --force

        # Every workload's images, so a CronJob between runs counts too.
        named=$(mktemp)
        trap 'rm -f "$named"' EXIT
        k3s kubectl get pods,replicasets,deployments,statefulsets,daemonsets,jobs,cronjobs -A -o json |
          jq -r '.. | objects | .image? // empty | strings | select(startswith("${registry}/"))
            | ltrimstr("${registry}/")' | sort -u >"$named"

        tags=${registryDir}/docker/registry/v2/repositories
        prune() {
          if [ -d "$tags" ]; then
            find "$tags" -path '*/_manifests/tags/*/current/link' "$@" -printf '%h\n' |
              while read -r current; do
                dir=''${current%/current}
                rel=''${dir#"$tags"/}
                grep -qxF "''${rel%%/_manifests/tags/*}:''${rel##*/}" "$named" || rm -rf "$dir"
              done
          fi
          registry garbage-collect --delete-untagged ${config.services.dockerRegistry.configFile}
        }
        systemctl stop docker-registry
        trap 'rm -f "$named"; systemctl start docker-registry' EXIT
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
