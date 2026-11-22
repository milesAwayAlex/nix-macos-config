# Postgres and Redis for the work code on the Mac, in the cluster's `services`
# namespace (D39). The images are built here from nixpkgs, imported by k3s,
# and run as declared below; lima forwards each LoadBalancer port to the
# Mac's 127.0.0.1, so the work code keeps `localhost:5432` and `:6379`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.devvm.services;
  namespace = "services";
  uid = 999;

  postgresql = pkgs.postgresql_16.withPackages (ps: [
    # Less its JIT bitcode, which pulls in clang and LLVM (2.5 GiB) for a
    # server built without JIT.
    (ps.postgis.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + "rm -r $out/lib/bitcode\n";
    }))
    ps.pgvector
  ]);
  # The dump names en_US.UTF-8 for every database, so the restore needs it.
  locales = pkgs.glibcLocales.override {
    allLocales = false;
    locales = [ "en_US.UTF-8/UTF-8" ];
  };
  # initdb and psql look the user up; the image has no other accounts.
  accounts = pkgs.runCommand "accounts" { } ''
    mkdir -p $out/etc
    echo "root:x:0:0::/root:/bin/sh" > $out/etc/passwd
    echo "app:x:${toString uid}:${toString uid}::/data:/bin/sh" >> $out/etc/passwd
    printf 'root:x:0:\napp:x:${toString uid}:\n' > $out/etc/group
  '';

  # A new data directory gets the locale (which also makes `english` the
  # text search default) and trust from anywhere: no passwords, as on the Mac.
  postgresStart = pkgs.writeShellScript "postgres-start" ''
    set -eu
    if [ ! -s "$PGDATA/PG_VERSION" ]; then
      ${postgresql}/bin/initdb --username=postgres --auth=trust \
        --encoding=UTF8 --locale=en_US.UTF-8
      echo "host all all all trust" >> "$PGDATA/pg_hba.conf"
    fi
    exec ${postgresql}/bin/postgres -c listen_addresses='*'
  '';

  image =
    name: imageConfig:
    pkgs.dockerTools.buildLayeredImage {
      name = "devvm.local/${name}";
      contents = [
        accounts
        pkgs.bashInteractive
        pkgs.coreutils
      ];
      extraCommands = "mkdir -m 1777 tmp";
      config = imageConfig // {
        User = "${toString uid}:${toString uid}";
      };
    };
  postgresImage = image "postgres" {
    Entrypoint = [ postgresStart ];
    Env = [
      "PATH=${postgresql}/bin:/bin"
      "PGDATA=/data/pgdata"
      # For psql here and the readiness check: the OS user has no role.
      "PGUSER=postgres"
      "LOCALE_ARCHIVE=${locales}/lib/locale/locale-archive"
      "LANG=en_US.UTF-8"
    ];
    # Fast shutdown: SIGTERM would wait for every client to disconnect.
    StopSignal = "SIGINT";
  };
  redisImage = image "redis" {
    Entrypoint = [
      "${pkgs.redis}/bin/redis-server"
      "--bind"
      "0.0.0.0"
      "--protected-mode"
      "no"
      "--dir"
      "/data"
    ];
    Env = [ "PATH=${pkgs.redis}/bin:/bin" ];
  };
  ref = img: "${img.imageName}:${img.imageTag}";

  # One server, its data on a local-path volume, a LoadBalancer port. The
  # volume outlives the StatefulSet; local-path deletes it with its claim.
  service =
    {
      name,
      img,
      port,
      memory,
      extraMounts ? [ ],
      extraVolumes ? [ ],
      probe,
    }:
    [
      {
        apiVersion = "apps/v1";
        kind = "StatefulSet";
        metadata = { inherit name namespace; };
        spec = {
          serviceName = name;
          replicas = 1;
          selector.matchLabels.app = name;
          template = {
            metadata.labels.app = name;
            spec = {
              # No fsGroup: local-path makes the volume 0777 already, and
              # fsGroup's chmod at every start leaves the data directory
              # group-writable, which postgres refuses.
              securityContext = {
                runAsUser = uid;
                runAsGroup = uid;
              };
              containers = [
                {
                  inherit name;
                  image = ref img;
                  # k3s imported it; there is nowhere to pull it from.
                  imagePullPolicy = "Never";
                  ports = [
                    {
                      inherit name;
                      containerPort = port;
                    }
                  ];
                  readinessProbe = {
                    exec.command = probe;
                    periodSeconds = 5;
                  };
                  resources = {
                    requests = {
                      cpu = "50m";
                      memory = "128Mi";
                    };
                    limits.memory = memory;
                  };
                  volumeMounts = [
                    {
                      name = "data";
                      mountPath = "/data";
                    }
                  ]
                  ++ extraMounts;
                }
              ];
              volumes = extraVolumes;
            };
          };
          volumeClaimTemplates = [
            {
              metadata.name = "data";
              spec = {
                accessModes = [ "ReadWriteOnce" ];
                # local-path does not enforce a size.
                resources.requests.storage = "10Gi";
              };
            }
          ];
        };
      }
      {
        apiVersion = "v1";
        kind = "Service";
        metadata = { inherit name namespace; };
        spec = {
          type = "LoadBalancer";
          selector.app = name;
          ports = [
            {
              inherit name port;
              targetPort = port;
            }
          ];
        };
      }
    ];
in
{
  options.devvm.services.enable = lib.mkEnableOption "Postgres and Redis for the Mac's work code, in the cluster";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.devvm.cluster.enable;
        message = "devvm.services needs devvm.cluster";
      }
    ];

    services.k3s.images = [
      postgresImage
      redisImage
    ];

    services.k3s.manifests.devvm-services.content = [
      {
        apiVersion = "v1";
        kind = "Namespace";
        metadata.name = namespace;
      }
    ]
    ++ service {
      name = "postgres";
      img = postgresImage;
      port = 5432;
      memory = "4Gi";
      probe = [
        "pg_isready"
        "-h"
        "127.0.0.1"
      ];
      # The unix socket's compiled-in directory, and room for parallel
      # queries' shared memory beyond the runtime's 64 MiB.
      extraMounts = [
        {
          name = "run";
          mountPath = "/run/postgresql";
        }
        {
          name = "shm";
          mountPath = "/dev/shm";
        }
      ];
      extraVolumes = [
        {
          name = "run";
          emptyDir = { };
        }
        {
          name = "shm";
          emptyDir = {
            medium = "Memory";
            sizeLimit = "1Gi";
          };
        }
      ];
    }
    ++ service {
      name = "redis";
      img = redisImage;
      port = 6379;
      memory = "1Gi";
      probe = [
        "redis-cli"
        "ping"
      ];
    };
  };
}
