# The dev VM's object store (D43): an S3 endpoint on this Mac for the
# cluster's backups. versitygw keeps each object as a plain file in one
# directory, outside the VM's disks and every directory the VM mounts, so a VM
# rebuilt from nothing loses nothing in it. Pods reach it through lima's
# gateway, 192.168.5.2, which is this Mac's loopback.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.devvm.objects;
  home = config.users.users.${config.system.primaryUser}.home;
  dir = "${home}/.local/share/devvm-objects";
  log = "${home}/Library/Logs/devvm-objects.log";
  port = toString cfg.port;
  endpoint = "http://127.0.0.1:${port}";
  # Login-keychain items: the admin's secret, made at the first start, and one
  # per bucket for its key. Values go to `security` and curl on stdin only.
  adminItem = "devvm-objects-admin";

  keychainSecret = import ./keychain-secret.nix;

  # `s3 METHOD PATH [CURL-ARGS...]` as the admin; a body that holds a secret
  # goes in $body, which reaches curl on stdin rather than its command line.
  asAdmin = ''
    if ! secret=$(/usr/bin/security find-generic-password -s ${adminItem} -a "$USER" -w 2>/dev/null); then
      echo "${adminItem} is not in the login keychain; devvm-objects makes it at its first start" >&2
      exit 1
    fi
    s3() {
      local method=$1 path=$2
      shift 2
      {
        printf 'user = "admin:%s"\n' "$secret"
        if [ -n "''${body:-}" ]; then printf 'data-binary = "%s"\n' "$body"; fi
      } | curl -sS --fail-with-body --aws-sigv4 aws:amz:us-east-1:s3 --config - \
        -X "$method" "$@" "${endpoint}$path"
    }
  '';

  devvm-objects-run = pkgs.writeShellApplication {
    name = "devvm-objects-run";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.versitygw
    ];
    text = keychainSecret + ''
      dir=${lib.escapeShellArg dir}
      mkdir -p "$dir/data" "$dir/versions" "$dir/iam"
      chmod 700 "$dir"
      ROOT_SECRET_KEY=$(keychain_secret ${adminItem})
      export ROOT_ACCESS_KEY=admin ROOT_SECRET_KEY
      # --quiet: no line per request in the log, which nothing would bound.
      # --fsync: a backup acknowledged is a backup on disk.
      exec versitygw --quiet --port 127.0.0.1:${port} --iam-dir "$dir/iam" \
        posix --fsync --versioning-dir "$dir/versions" "$dir/data"
    '';
  };

  # A versioned bucket and its own key. The admin owns the bucket; the key may
  # read, write, list and delete objects, and nothing else: no deleting old
  # versions, no changing the bucket's settings or its policy.
  devvm-objects-bucket = pkgs.writeShellApplication {
    name = "devvm-objects-bucket";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];
    text =
      keychainSecret
      + asAdmin
      + ''
        name=''${1:-}
        if ! [[ $name =~ ^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$ ]]; then
          echo "usage: devvm-objects-bucket NAME (3 to 63 of a-z, 0-9 and -)" >&2
          exit 64
        fi
        item=devvm-objects-$name
        key=$(keychain_secret "$item")

        body="<Account><Access>$name</Access><Secret>$key</Secret><Role>user</Role></Account>" \
          s3 PATCH /create-user -o /dev/null 2>/dev/null ||
          body="<MutableProps><Secret>$key</Secret></MutableProps>" \
            s3 PATCH "/update-user?access=$name" -o /dev/null

        s3 PUT "/$name" -o /dev/null 2>/dev/null || s3 GET "/$name?versioning" -o /dev/null
        s3 PUT "/$name?versioning" -o /dev/null --data-binary \
          '<VersioningConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Status>Enabled</Status></VersioningConfiguration>'
        s3 PUT "/$name?policy" -o /dev/null --data-binary "$(jq -cn --arg b "$name" '{
          Version: "2012-10-17",
          Statement: [
            { Effect: "Allow", Principal: { AWS: [$b] }, Resource: ["arn:aws:s3:::\($b)"],
              Action: ["s3:ListBucket", "s3:ListBucketVersions", "s3:GetBucketLocation", "s3:GetBucketVersioning"] },
            { Effect: "Allow", Principal: { AWS: [$b] }, Resource: ["arn:aws:s3:::\($b)/*"],
              Action: ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject",
                       "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"] }
          ]
        }')"

        echo "bucket $name: versioned, a version kept ${toString cfg.keepDays} days after it is replaced"
        echo "  endpoint: http://192.168.5.2:${port} from the cluster, ${endpoint} from this Mac"
        echo "  region us-east-1, path-style; access key id $name"
        echo "  secret: security find-generic-password -s $item -a \"\$USER\" -w"
      '';
  };

  # The lifecycle rule versitygw does not have: a version goes keepDays after
  # the one that replaced it, not after it was written, so a wipe of a bucket's
  # current objects leaves keepDays to undo it; then a delete marker left
  # alone goes too.
  devvm-objects-expire = pkgs.writeShellApplication {
    name = "devvm-objects-expire";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
      pkgs.yq-go
    ];
    text = asAdmin + ''
      days=${toString cfg.keepDays}
      dry=
      while [ $# -gt 0 ]; do
        case $1 in
          --dry-run) dry=1 ;;
          --days)
            days=$2
            shift
            ;;
          -*)
            echo "usage: devvm-objects-expire [--dry-run] [--days N] [BUCKET...]" >&2
            exit 64
            ;;
          *) break ;;
        esac
        shift
      done
      cutoff=$(date -u -d "$days days ago" +%Y-%m-%dT%H:%M:%S)
      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT
      # yq makes an object of one element and an array of several.
      arr='def arr: if . == null or . == "" then [] elif type == "array" then . else [.] end;'

      if [ $# -gt 0 ]; then
        buckets=("$@")
      else
        mapfile -t buckets < <(s3 GET / | yq -p xml -o json |
          jq -r "$arr"' .ListAllMyBucketsResult.Buckets.Bucket | arr[] | .Name')
      fi

      for bucket in "''${buckets[@]}"; do
        : >"$tmp/versions"
        marker=
        while :; do
          s3 GET "/$bucket?versions&max-keys=1000$marker" | yq -p xml -o json >"$tmp/page"
          jq -c "$arr"' .ListVersionsResult
            | (.Version | arr[] | {Key, VersionId, LastModified, marker: false}),
              (.DeleteMarker | arr[] | {Key, VersionId, LastModified, marker: true})' \
            "$tmp/page" >>"$tmp/versions"
          [ "$(jq -r '.ListVersionsResult.IsTruncated' "$tmp/page")" = true ] || break
          marker=$(jq -r '.ListVersionsResult
            | "&key-marker=\(.NextKeyMarker | @uri)&version-id-marker=\(.NextVersionIdMarker | @uri)"' "$tmp/page")
        done
        # Newest first per key; version IDs are ULIDs, so they break ties.
        jq -rs --arg cutoff "$cutoff" '
          group_by(.Key)[]
          | sort_by(.LastModified, .VersionId) | reverse | . as $v
          | (range(1; length) | $v[.] + {since: $v[. - 1].LastModified} | select(.since < $cutoff)),
            (select(length == 1 and .[0].marker and .[0].LastModified < $cutoff) | .[0])
          | [.Key, .VersionId] | @tsv' "$tmp/versions" >"$tmp/expired"
        n=0
        while IFS=$'\t' read -r key vid; do
          n=$((n + 1))
          [ -n "$dry" ] && continue
          path=$(jq -rn --arg k "$key" '$k | split("/") | map(@uri) | join("/")')
          s3 DELETE "/$bucket/$path?versionId=$vid" -o /dev/null
        done <"$tmp/expired"
        echo "devvm-objects-expire: $(date '+%F %T') $bucket: ''${dry:+would remove }$n version(s) replaced before $cutoff UTC"
      done
    '';
  };
in
{
  options.devvm.objects = {
    enable = lib.mkEnableOption "an S3 object store on this Mac for the dev VM's cluster";
    port = lib.mkOption {
      type = lib.types.port;
      default = 7070;
      description = "Loopback port; the cluster reaches it at 192.168.5.2.";
    };
    keepDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "Days an object version is kept after another replaces it.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      devvm-objects-bucket
      devvm-objects-expire
    ];

    # Up from login to logout. A user agent: the data and the keychain are
    # the user's.
    launchd.user.agents.devvm-objects.serviceConfig = {
      ProgramArguments = [ (lib.getExe devvm-objects-run) ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      StandardOutPath = log;
      StandardErrorPath = log;
    };

    launchd.user.agents.devvm-objects-expire.serviceConfig = {
      ProgramArguments = [ (lib.getExe devvm-objects-expire) ];
      StartCalendarInterval = [
        {
          Hour = 6;
          Minute = 0;
        }
      ];
      ProcessType = "Background";
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
}
