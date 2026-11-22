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
  # The variable the guest's credential store reads; published by the guest so
  # the two halves cannot disagree on it.
  authEnv = roles.containers.registryAuthEnv;

  keyFile = "/etc/nix/devvm_ed25519";
  knownHosts = "/etc/nix/devvm_known_hosts";
  # Where lima puts the guest's kubeconfig while the VM runs; `{{.Dir}}` below
  # is lima's own spelling of the same directory.
  kubeconfig = "$HOME/.lima/${name}/copied-from-guest/kubeconfig.yaml";

  # launchd's name for the job that keeps the VM, and where both jobs put
  # what they print themselves: a directory that is always there.
  agentLabel = config.launchd.user.agents.devvm.serviceConfig.Label;
  agentLog = "${config.users.users.${config.system.primaryUser}.home}/Library/Logs/devvm.log";

  limaYaml = (pkgs.formats.yaml { }).generate "lima-${name}.yaml" (
    {
      # Apple Virtualization rather than qemu: virtiofs instead of 9p, and no
      # emulation layer to pay for on aarch64 hosting aarch64.
      vmType = "vz";
      arch = "aarch64";
      nestedVirtualization = cfg.nestedVirtualization;

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
      # Over lima's virtual network, not vsock. lima's vsock forwarder cannot
      # pass the Mac's EOF on to the guest (the vz connection has no half-close),
      # so the guest's per-connection sshd instance outlives every connection nix
      # closes, and systemd caps those instances at 64: the builder went dark on
      # the 65th remote build of a boot. Over TCP a closed socket is a FIN and
      # the session ends with it.
      ssh.overVsock = false;

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

  # The Mac's half of the guest's credential store. For each host in
  # `registryAuth`: the last answer, if it carried an expiry still a minute
  # ahead, otherwise the command; out comes the object the guest's helper reads.
  # Answers with an expiry are kept 0600 in the per-user temp directory — the
  # same place, and the same exposure, as gcloud's own token store; answers
  # without one are never written down. A failing command costs that host its
  # credentials and says so, and the call goes on: the pull then fails at the
  # registry rather than here.
  devvm-registry-auth = pkgs.writeShellApplication {
    name = "devvm-registry-auth";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      cache="''${TMPDIR:-/tmp}/devvm-registry-auth"
      install -d -m 0700 "$cache"
      umask 077
      declare -A commands=(${
        lib.concatStringsSep " " (
          lib.mapAttrsToList (
            host: command: "[${lib.escapeShellArg host}]=${lib.escapeShellArg command}"
          ) cfg.registryAuth
        )
      })
      auth='{}'
      for host in "''${!commands[@]}"; do
        file="$cache/$host"
        if [ -f "$file" ] && jq -e '(.ExpiresAt | fromdateiso8601) > now + 60' "$file" >/dev/null 2>&1; then
          cred=$(cat "$file")
        else
          if ! cred=$(bash -c "''${commands[$host]}") ||
            ! jq -e 'has("Username") and has("Secret")' <<<"$cred" >/dev/null 2>&1; then
            echo "devvm: no credentials for $host (its command failed or printed no {Username, Secret}); going on without them, so only public images pull from it" >&2
            continue
          fi
          if jq -e 'has("ExpiresAt")' <<<"$cred" >/dev/null; then
            printf '%s' "$cred" > "$file"
          fi
        fi
        auth=$(jq -c --arg h "$host" --argjson c "$cred" '.[$h] = ($c | {Username, Secret})' <<<"$auth")
      done
      printf '%s' "$auth"
    '';
  };

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
  #
  # Credentials: resolved here for the hosts in `registryAuth` and delivered in
  # one variable, for this call only. lima forwards the environment as an `env`
  # prefix on the ssh command line, so that variable is held back from the
  # forwarding and sent through ssh's own SendEnv instead — lima takes the ssh
  # command line from `$SSH` — which keeps it off every process list on the
  # way; the guest's sshd accepts exactly this name.
  #
  # Identity: `docker -v` answers as nerdctl, and that is load-bearing. kind's
  # provider detection reads that first line, takes docker only when it says
  # "Docker version", and asks `nerdctl -v` next — which is how kind on this
  # Mac lands on the nerdctl provider by itself. A wrapper that faked the
  # banner for some tool that sniffs it would send kind down the docker path
  # onto nerdctl.
  shim =
    bin: target:
    pkgs.writeShellScriptBin bin ''
      export LIMA_SHELLENV_BLOCK="+LC_*,LANG,LANGUAGE"
      ${lib.optionalString (cfg.registryAuth != { }) ''
        ${authEnv}=$(${devvm-registry-auth}/bin/devvm-registry-auth)
        export ${authEnv} SSH="ssh -o SendEnv=${authEnv}" LIMA_SHELLENV_BLOCK="$LIMA_SHELLENV_BLOCK,SSH,${authEnv}"
      ''}
      workdir=/var/empty
      ${lib.optionalString (cfg.mount != null) ''
        case "$PWD" in ${cfg.mount} | ${cfg.mount}/*) workdir="$PWD" ;; esac
      ''}
      exec ${cfg.package}/bin/limactl shell --preserve-env --workdir "$workdir" ${name} ${target} "$@"
    '';

  # What launchd runs to keep the VM (D36): the host agent in the foreground,
  # so the VM lives exactly as long as the job. `limactl start` becomes the
  # agent, which shuts the guest down when launchd asks it to stop.
  devvm-run = pkgs.writeShellApplication {
    name = "devvm-run";
    runtimeInputs = [
      cfg.package
      pkgs.gnugrep
    ];
    text = ''
      # Nothing to keep without an instance, and `limactl start` would make
      # one from lima's default template. One started by hand is left alone.
      # Both are clean exits, which launchd does not answer.
      status=$(limactl list ${name} --format '{{.Status}}' 2>/dev/null || true)
      if [ -z "$status" ] || [ "$status" = Running ]; then
        exit 0
      fi
      ${lib.optionalString cfg.keepAwake ''
        # No system sleep on AC power while this process lives, which after
        # the exec below is the host agent (D37). On battery it holds nothing.
        /usr/bin/caffeinate -s -w $$ &
      ''}
      # The files lima itself writes when it starts the agent detached, so
      # the logs are where DEVVM.md says, whoever started the VM. Less the
      # agent's debug lines, written at any log level: four per proxied
      # connection, about 15 MB a day for as long as the VM runs.
      exec limactl start --foreground --tty=false ${name} \
        >"$HOME/.lima/${name}/ha.stdout.log" \
        2> >(grep --line-buffered -v '"level":"debug"' >"$HOME/.lima/${name}/ha.stderr.log")
    '';
  };

  # Every check the layers above the instance have a known answer for: what is
  # wrong, and the cure DEVVM.md gives. It changes nothing (D36). `--notify`
  # is launchd's run: silent, and a notification when the verdict has changed
  # and held for two runs, so a boot or a wake is not reported as a fault.
  # The cluster's Postgres, whole, into the shared directory, replacing the
  # last dump (D39).
  postgres-dump = pkgs.writeShellApplication {
    name = "postgres-dump";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gzip
      pkgs.postgresql_16
    ];
    text = ''
      dir=${lib.escapeShellArg "${cfg.mount}/postgres-dumps"}
      mkdir -p "$dir"
      pg_dumpall -h 127.0.0.1 -U postgres | gzip > "$dir/.postgres.sql.gz.tmp"
      mv "$dir/.postgres.sql.gz.tmp" "$dir/postgres.sql.gz"
      echo "postgres-dump: $(date '+%F %T') $(du -h "$dir/postgres.sql.gz" | cut -f1)"
    '';
  };

  devvm-doctor = pkgs.writeShellApplication {
    name = "devvm-doctor";
    runtimeInputs = [
      cfg.package
      pkgs.coreutils
      pkgs.gnused
      pkgs.gawk
      pkgs.jq
    ]
    ++ lib.optional roles.cluster.enable pkgs.kubectl;
    text = ''
      name=${name}
      notify=
      case "''${1:-}" in
        --notify) notify=1 ;;
        "") ;;
        *)
          echo "usage: devvm-doctor [--notify]" >&2
          exit 64
          ;;
      esac

      # A fault is an id, what is wrong and what to do, tab-separated. A note
      # is something worth saying that is not this tool's to call a fault.
      faults=()
      notes=()
      fault() { faults+=("$1"$'\t'"$2"$'\t'"$3"); }

      # Whether a connection to a local port is taken and hung up at once:
      # what a forward does with nothing behind it. A subshell, for the
      # descriptor; the same test runs in the guest, below.
      hangs_up() (
        exec 3<>"/dev/tcp/127.0.0.1/$1" || exit 2
        rc=0
        read -r -t 0.3 -n 1 -u 3 _ || rc=$?
        [ "$rc" -ne 0 ] && [ "$rc" -le 128 ]
      ) 2>/dev/null

      examine() {
        local status facts now skew failed used disk job port alive
        local -a dead=()
        status=$(limactl list "$name" --format '{{.Status}}' 2>/dev/null || true)
        if [ -z "$status" ]; then
          fault instance "the instance does not exist" "just devvm-up (DEVVM.md, Bootstrap)"
          return
        fi
        if [ "$status" != Running ]; then
          fault instance "the instance is $status" "just devvm-up"
          return
        fi

        if job=$(launchctl print "gui/$(id -u)/${agentLabel}" 2>/dev/null) &&
          [ "$(sed -n 's/^[[:space:]]*pid = //p' <<<"$job" | head -n 1)" != "$(cat "$HOME/.lima/$name/ha.pid" 2>/dev/null)" ]; then
          notes+=("started by hand, so launchd is not keeping it: just devvm-down, then just devvm-up")
        ${lib.optionalString cfg.keepAwake ''
          # launchd's VM, and nothing holding the Mac awake for it: a host
          # agent from before keepAwake, or a caffeinate that died.
          elif [ -n "$job" ] && ! /usr/bin/pgrep -qf "caffeinate -s -w $(cat "$HOME/.lima/$name/ha.pid")\$"; then
            fault awake "nothing keeps the Mac awake for the VM on AC power" "just devvm-down, then just devvm-up"
        ''}
        fi

        # One round trip for everything the guest has to say about itself.
        # Single quotes on purpose: this expands in the guest, not here.
        # shellcheck disable=SC2016
        if ! facts=$(timeout 20 limactl shell --workdir / "$name" sudo sh -c '
            echo "now=$(date +%s)"
            echo "failed=$(systemctl list-units --failed --no-legend --plain | cut -d" " -f1 | tr "\n" " ")"
            echo "root_used=$(df --output=pcent / | tail -n 1 | tr -dc 0-9)"
            ${lib.optionalString (roles.stateDisk != null) ''
              mountpoint -q ${roles.stateDir} && echo "state=mounted"
              echo "state_used=$(df --output=pcent ${roles.stateDir} | tail -n 1 | tr -dc 0-9)"
            ''}
            ${lib.optionalString (cfg.mount != null) ''
              mountpoint -q ${cfg.mount} && echo "share=mounted"
            ''}
            ${lib.optionalString roles.cluster.enable ''
              k3s kubectl get --raw /readyz >/dev/null 2>&1 && echo "api=ready"
              pgrep -x kubectl >/dev/null && echo "watch=running"
            ''}
            exit 0
          ' 2>/dev/null); then
          fault guest "the guest does not answer over ssh" "limactl restart $name"
          return
        fi
        fact() { sed -n "s/^$1=//p" <<<"$facts"; }

        now=$(fact now)
        if [ -z "$now" ]; then
          fault guest "the guest answered with nothing" "limactl restart $name"
          return
        fi
        skew=$((now - $(date +%s)))
        if [ "''${skew#-}" -gt 5 ]; then
          fault clock "the guest's clock is ''${skew}s from the Mac's" \
            "just devvm-shell sudo systemctl restart lima-guestagent"
        fi

        # Every port the host agent listens on is a forward. One that hangs
        # up here and not in the guest has lost the connection it was made
        # with: a guest agent restart can leave that on some ports and not
        # on others, and ssh, on a forward of its own, never shows it.
        for port in $(/usr/sbin/lsof -nP -a -p "$(cat "$HOME/.lima/$name/ha.pid")" -iTCP -sTCP:LISTEN -Fn 2>/dev/null |
          sed -n 's/^n.*:\([0-9]*\)$/\1/p' | sort -un); do
          if hangs_up "$port"; then
            dead+=("$port")
          fi
        done
        if [ ''${#dead[@]} -gt 0 ]; then
          # shellcheck disable=SC2016
          alive=$(timeout 20 limactl shell --workdir / "$name" bash -c '
            for port in "$@"; do
              (
                exec 3<>"/dev/tcp/127.0.0.1/$port" || exit 1
                rc=0
                read -r -t 0.3 -n 1 -u 3 _ || rc=$?
                [ "$rc" -eq 0 ] || [ "$rc" -gt 128 ]
              ) 2>/dev/null && printf "%s " "$port"
            done
            exit 0
          ' _ "''${dead[@]}" 2>/dev/null || true)
          if [ -n "$alive" ]; then
            fault forwards "lima's port forwards are stale: ''${alive% } answer in the guest and not on the Mac" \
              "limactl restart $name (DEVVM.md, When it breaks)"
          fi
        fi

        failed=$(fact failed)
        if [ -n "''${failed// /}" ]; then
          fault units "failed units in the guest: $failed" "just devvm-shell systemctl status $failed"
        fi

        for disk in root state; do
          used=$(fact "''${disk}_used")
          if [ -n "$used" ] && [ "$used" -ge 90 ]; then
            fault "disk-$disk" "the guest's $disk disk is $used% full" \
              "DEVVM.md, When it breaks: the guest's disk fills"
          fi
        done
        ${lib.optionalString (roles.stateDisk != null) ''
          if [ "$(fact state)" != mounted ]; then
            fault state "the state disk is not mounted in the guest" \
              "just devvm-shell journalctl -u devvm-state-disk (DEVVM.md, When it breaks)"
          fi
        ''}
        ${lib.optionalString (cfg.mount != null) ''
          if [ "$(fact share)" != mounted ]; then
            fault share "${cfg.mount} is not mounted in the guest" \
              "just devvm-shell sudo systemctl restart lima-init"
          fi
        ''}
        ${lib.optionalString roles.cluster.enable ''
          local kubeconfig="${kubeconfig}" context=${guest.networking.hostName}
          local nodes pods svcs bad svc port holder
          k() { kubectl --kubeconfig "$kubeconfig" --request-timeout=5s "$@"; }

          if [ "$(fact api)" != ready ]; then
            fault k3s "k3s is not answering in the guest" \
              "it restarts itself; just devvm-shell journalctl -u k3s -n 50 if it stays down"
            return
          fi
          if [ ! -f "$kubeconfig" ]; then
            fault kubeconfig "the kubeconfig has not been copied to the Mac" \
              "limactl restart $name (DEVVM.md, When it breaks)"
            return
          fi
          if ! k version >/dev/null 2>&1; then
            fault api "the API answers in the guest and not on the Mac" \
              "limactl restart $name (DEVVM.md, When it breaks)"
            return
          fi
          if ! nodes=$(k get nodes -o json 2>/dev/null) ||
            ! pods=$(k get pods -A -o json 2>/dev/null) ||
            ! svcs=$(k get services -A -o json 2>/dev/null); then
            fault api "the API stopped answering part-way through" "devvm-doctor again"
            return
          fi

          # Ready has to be True and every other condition, the pressures, not.
          bad=$(jq -r '.items[] | .metadata.name as $n | .status.conditions[]
            | select((.type == "Ready") != (.status == "True"))
            | "\($n) \(.type)=\(.status)"' <<<"$nodes" | tr '\n' ' ')
          if [ -n "$bad" ]; then
            fault node "node condition: $bad" "kubectl --context $context describe nodes"
          fi

          # Not running, or running with a container that is not ready.
          pods=$(jq -r '.items[] | select(.status.phase != "Succeeded")
            | select(.status.phase != "Running" or ([.status.containerStatuses[]?.ready] | all | not))
            | "\(.metadata.namespace)/\(.metadata.name)"' <<<"$pods")
          bad=$(awk -F/ '$1 == "kube-system"' <<<"$pods" | tr '\n' ' ')
          if [ -n "$bad" ]; then
            fault pods "system pods not running: $bad" "kubectl --context $context -n kube-system get pods"
          fi
          bad=$(awk -F/ 'NF && $1 != "kube-system"' <<<"$pods" | tr '\n' ' ')
          if [ -n "$bad" ]; then
            notes+=("pods not running outside kube-system: $bad")
          fi

          # A service the Mac should reach is a listener the host agent holds:
          # a LoadBalancer under its own port, a NodePort under the node's.
          while read -r svc port; do
            [ -n "$port" ] || continue
            if /usr/sbin/lsof -nP -a -p "$(cat "$HOME/.lima/$name/ha.pid")" -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
              continue
            fi
            holder=$(/usr/sbin/lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR == 2 {print $1}')
            if [ -n "$holder" ]; then
              fault "port-$port" "service $svc: port $port on the Mac is held by $holder" \
                "stop it, or move the service; lima forwards the port once it is free"
            elif [ "$(fact watch)" != running ]; then
              fault "port-$port" "service $svc: port $port is not forwarded, the guest agent has no kubectl watch" \
                "just devvm-rebuild, limactl restart $name (DEVVM.md, When it breaks)"
            else
              fault "port-$port" "service $svc: port $port is not forwarded to the Mac" \
                "look for $port in ~/.lima/$name/ha.stderr.log"
            fi
          done < <(jq -r '.items[] | . as $s
            | select(.spec.type == "LoadBalancer" or .spec.type == "NodePort")
            | .spec.ports[] | select((.protocol // "TCP") == "TCP")
            | "\($s.metadata.namespace)/\($s.metadata.name) \(if $s.spec.type == "LoadBalancer" then .port else .nodePort end)"' <<<"$svcs")
        ''}
      }

      report() {
        local entry what cure
        if [ ''${#faults[@]} -eq 0 ]; then
          echo "$name: healthy"
        else
          echo "$name: ''${#faults[@]} fault(s)"
        fi
        for entry in "''${faults[@]}"; do
          IFS=$'\t' read -r _ what cure <<<"$entry"
          printf '  ✗ %s\n      %s\n' "$what" "$cure"
        done
        for entry in "''${notes[@]}"; do
          printf '  · %s\n' "$entry"
        done
      }

      examine
      if [ -z "$notify" ]; then
        report
        [ ''${#faults[@]} -eq 0 ]
        exit
      fi

      state="''${XDG_STATE_HOME:-$HOME/.local/state}/devvm"
      mkdir -p "$state"
      { date '+%F %T %z'; report; } >"$state/report"

      # The verdict is the set of fault ids. `seen` is the last run's, `told`
      # the last one a notification went out for.
      verdict=$(for entry in "''${faults[@]}"; do echo "''${entry%%$'\t'*}"; done | sort | tr '\n' ' ')
      seen=$(cat "$state/seen" 2>/dev/null || true)
      told=$(cat "$state/told" 2>/dev/null || true)
      printf '%s' "$verdict" >"$state/seen"
      if [ "$verdict" = "$seen" ] && [ "$verdict" != "$told" ]; then
        if [ ''${#faults[@]} -eq 0 ]; then
          message="healthy again"
        else
          IFS=$'\t' read -r _ message _ <<<"''${faults[0]}"
          if [ ''${#faults[@]} -gt 1 ]; then
            message="$message, and $((''${#faults[@]} - 1)) more: devvm-doctor"
          fi
        fi
        /usr/bin/osascript -e 'on run argv' \
          -e 'display notification (item 1 of argv) with title "devvm"' \
          -e 'end run' "$message" >/dev/null 2>&1 || true
        printf '%s' "$verdict" >"$state/told"
        cat "$state/report" >>"$state/doctor.log"
      fi
    '';
  };

  devvm-status = pkgs.writeShellApplication {
    name = "devvm-status";
    runtimeInputs = [
      cfg.package
      pkgs.kubectl
      pkgs.openssh
      pkgs.jq
    ];
    text = ''
      name=${name}

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
        echo "   verify   sudo -H nix store info --store ssh-ng://$name"
      ''}

      ${lib.optionalString (cfg.registryAuth != { }) ''
        echo "── registry credentials (resolved here, delivered per call)"
        hosts=(${lib.escapeShellArgs (lib.attrNames cfg.registryAuth)})
        for host in "''${hosts[@]}"; do
          file="''${TMPDIR:-/tmp}/devvm-registry-auth/$host"
          if [ -f "$file" ]; then
            printf '   %-20s cached until %s\n' "$host" "$(jq -r '.ExpiresAt' "$file")"
          else
            printf '   %-20s asked for on every call\n' "$host"
          fi
        done
      ''}

      if [ "$status" != "Running" ]; then
        echo "── guest: instance is $status"
        exit 0
      fi

      ${lib.optionalString (cfg.mount != null) ''
        # lima-init mounts the share through /etc/fstab and a guest generation
        # from before the activation remount lost it at every rebuild, for six
        # days, silently.
        echo "── share"
        if limactl shell "$name" mountpoint -q ${cfg.mount} 2>/dev/null; then
          echo "   ${cfg.mount}  mounted"
        else
          echo "   ${cfg.mount}  NOT mounted — \`just devvm-shell sudo systemctl restart lima-init\` (DEVVM.md, When it breaks)"
        fi
      ''}

      ${lib.optionalString roles.cluster.enable ''
        # Set here and not at the top: shellcheck fails the build on a
        # variable a builder-only role never reads.
        kubeconfig="${kubeconfig}"
        echo "── cluster"
        if [ -f "$kubeconfig" ]; then
          if KUBECONFIG="$kubeconfig" kubectl version --request-timeout=5s >/dev/null 2>&1; then
            KUBECONFIG="$kubeconfig" kubectl get nodes \
              --no-headers -o 'custom-columns=:.metadata.name,:.status.conditions[-1].type' 2>/dev/null |
              sed 's/^/   node     /'
            printf '   pods     '
            KUBECONFIG="$kubeconfig" kubectl get pods -A --no-headers 2>/dev/null |
              awk '{c[$4]++} END {for (s in c) printf "%s=%s ", s, c[s]; print ""}'
          elif limactl shell "$name" sudo k3s kubectl get --raw /readyz >/dev/null 2>&1; then
            # ssh rides a forward of its own, so everything above this line
            # stays green while lima's port forwards are dead.
            echo "   api      up in the guest, unreachable from here: a stale forward — \`limactl restart $name\` (DEVVM.md, When it breaks)"
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
      cfg.package
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
  # The start is launchd's wherever its job is loaded (D36), so that a VM
  # brought up by hand is kept like one brought up at login.
  devvm-up = pkgs.writeShellApplication {
    name = "devvm-up";
    runtimeInputs = [
      cfg.package
      pkgs.coreutils
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
      if [ "$(limactl list ${name} --format '{{.Status}}')" = Running ]; then
        echo "${name} is running"
        exit 0
      fi

      job="gui/$(id -u)/${agentLabel}"
      if ! launchctl print "$job" >/dev/null 2>&1; then
        exec limactl start ${name}
      fi
      # The host agent reports on its standard output, which the job sends
      # to this file; emptied first, so the last run's "running" is not read.
      events="$HOME/.lima/${name}/ha.stdout.log"
      : >"$events"
      launchctl kickstart "$job"
      echo "starting ${name} under launchd; its log is ~/.lima/${name}/ha.stderr.log"
      for _ in {1..300}; do
        sleep 2
        if grep -q '"degraded":true' "$events"; then
          echo "${name} is DEGRADED (DEVVM.md, When it breaks)" >&2
          exit 1
        elif grep -q '"running":true' "$events"; then
          echo "${name} is running"
          exit 0
        elif grep -q '"exiting":true' "$events"; then
          break
        fi
      done
      echo "${name} did not come up: ~/.lima/${name}/ha.stderr.log, and ${agentLog} for the job itself" >&2
      exit 1
    '';
  };
in
{
  options.devvm = {
    enable = lib.mkEnableOption "the local Linux development VM";

    # Every tool here and the host agent run this one lima; the guest agent
    # is the one it ships, handed to the guest at each start.
    package = lib.mkPackageOption pkgs "lima" { };

    keepAwake = lib.mkEnableOption ''
      keeping the Mac from system sleep while the VM runs and the Mac is on
      AC power, for a guest that has work to do when nobody is at the
      keyboard. The display still sleeps and locks, and on battery the Mac
      sleeps as it always did
    '';

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

    registryAuth = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = lib.literalExpression ''{ "gcr.io" = lib.getExe gcloudRegistryCredential; }'';
      description = ''
        Registry hosts this Mac answers for, each with a command that prints
        the credential as JSON — `{"Username": …, "Secret": …}`, plus
        `"ExpiresAt": "2026-09-05T23:26:25Z"` (that exact form, UTC) when it
        is a token with a known life. The wrappers run the command, keep an
        answer with an expiry until it expires, and hand the result to the
        guest's nerdctl for the duration of each call. A credential without an
        expiry is asked for on every call and never written down, so its
        command has to answer quickly and silently. Nothing here is a
        credential; the commands are.
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
    nestedVirtualization = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Let the guest run hardware-accelerated VMs of its own; Apple
        Virtualization nests from M3 on. Disabled by default because nested
        KVM builds can hang or fault on the tested macOS setup (D22).
        Without /dev/kvm, VM-backed builds use QEMU's TCG fallback. Use
        `just devvm-kvm-check` to test KVM before enabling it permanently.
      '';
    };
    disk = lib.mkOption {
      type = lib.types.str;
      default = "60GiB";
      description = "The OS disk. Disposable: every rebuild rewrites it.";
    };
    stateDiskSize = lib.mkOption {
      type = lib.types.str;
      default = "40GiB";
      description = ''
        Size of the volume the guest's `devvm.stateDisk` names. `devvm-up`
        creates it at this size and never looks again; DEVVM.md has the
        steps that grow an existing one.
      '';
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
      example = "/Users/alex/code-shared";
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
          cfg.package
          # Deploys a guest change from here: the Mac evaluates, the guest builds
          # and activates its own system over lima's ssh. The builder role is not
          # involved, so a guest without it deploys the same way.
          (pkgs.nixos-rebuild.overrideAttrs (old: {
            # The upstream test leaves fixed /tmp directories owned by one
            # nixbld user, so the next user's build fails. Give each test run
            # fresh directories with cleanup, keeping both path-length cases.
            # Remove once nixpkgs' test_tmpdir.py uses unique directories.
            postPatch = (old.postPatch or "") + ''
              substituteInPlace tests/test_tmpdir.py \
                --replace-fail 'with system_tempdir(Path("/tmp/not-too-long")):' \
                  'with tempfile.TemporaryDirectory(prefix="nr-", dir="/tmp") as path, system_tempdir(Path(path)):' \
                --replace-fail 'with system_tempdir(Path("/tmp/long" + ("g" * MAX_TMPDIR_LENGTH))):' \
                  'with tempfile.TemporaryDirectory(prefix="long" + ("g" * MAX_TMPDIR_LENGTH), dir="/tmp") as path, system_tempdir(Path(path)):'
            '';
          }))
          devvm-up
          devvm-run
          devvm-status
          devvm-doctor
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

        # The VM is up from login to logout, and comes back from a crash
        # (D36). A user agent: ~/.lima and the host agent are per-user.
        launchd.user.agents.devvm.serviceConfig = {
          # By its profile path, not its store path: nix-darwin reloads an
          # agent whose plist changed, and a reload here restarts the VM. A
          # new lima reaches the VM at its next start, as it always has.
          # The system profile and not /run/current-system, which is linked
          # only after the agents are loaded: on the switch that first adds
          # this job launchd finds no program there and never tries again.
          ProgramArguments = [ "${config.system.profile}/sw/bin/devvm-run" ];
          RunAtLoad = true;
          # `limactl stop` ends the host agent cleanly, and stopped has to
          # stay stopped; any other exit is a crash to come back from.
          KeepAlive.SuccessfulExit = false;
          ThrottleInterval = 30;
          # Room for a loaded guest to shut down before launchd kills the
          # job: 5 to 7 seconds measured, and launchd's own limit is 20.
          ExitTimeOut = 90;
          # Not Background, which confines a job to the efficiency cores.
          ProcessType = "Standard";
          StandardOutPath = agentLog;
          StandardErrorPath = agentLog;
        };

        # The checks, every two minutes; it reports and repairs nothing.
        launchd.user.agents.devvm-doctor.serviceConfig = {
          ProgramArguments = [
            (lib.getExe devvm-doctor)
            "--notify"
          ];
          StartInterval = 120;
          ProcessType = "Background";
          StandardOutPath = agentLog;
          StandardErrorPath = agentLog;
        };
      }

      (lib.mkIf roles.cluster.enable {
        # kubectl, k9s and kubectx read a colon-separated list and merge it. The
        # Mac's own file stays first, so gcloud keeps writing there and nothing
        # is ever merged into it. The guest's context appears under the guest's
        # name while the VM runs and vanishes with it: kubectl skips a missing
        # file, and fails fast if the current context lived in it.
        environment.variables.KUBECONFIG = "$HOME/.kube/config:${kubeconfig}";
      })

      (lib.mkIf roles.services.enable {
        # The cluster's Postgres and Redis (D39) reach this Mac as lima's
        # forwards on 127.0.0.1:5432 and :6379. PGHOST because psql's default
        # is a unix socket here, and no server runs here now.
        environment.systemPackages = [
          pkgs.postgresql_16
          pkgs.redis
        ];
        environment.variables.PGHOST = "127.0.0.1";
      })

      (lib.mkIf (roles.services.enable && cfg.mount != null) {
        environment.systemPackages = [ postgres-dump ];
        launchd.user.agents.postgres-dump.serviceConfig = {
          ProgramArguments = [ (lib.getExe postgres-dump) ];
          StartCalendarInterval = [
            {
              Hour = 2;
              Minute = 0;
            }
          ];
          ProcessType = "Background";
          StandardOutPath = agentLog;
          StandardErrorPath = agentLog;
        };
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
            # `kvm` unconditionally, as nix-darwin's linux-builder does. Nix
            # schedules by this list, and the guest is NixOS, whose daemon
            # declares the feature whether or not /dev/kvm exists, so it never
            # refuses such a build: in the sandbox nix binds the device when it
            # is there and warns when it is not, and qemu's `accel=kvm:tcg`
            # falls back to emulation.
            supportedFeatures = [
              "benchmark"
              "big-parallel"
              "kvm"
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
