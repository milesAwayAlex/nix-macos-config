# The dev VM

One lima instance, `devvm`, whose guest OS is one of two role sets this flake
exports as `nixosConfigurations`: `devvm` — the `aarch64-linux` builder the nix
daemon on the Mac uses, a containerd with nerdctl and buildkit, and a k3s
cluster — and `devvm-builder`, the first alone. The Mac names the one it runs
in its host file: `work` runs `devvm`, `personal` the builder alone. The why is PLAN.md Phase 8 and D22/D23. This is the operating manual for both
halves — `modules/nixos/devvm` (the guest) and `modules/darwin/devvm.nix` (the
host) — and for the `just devvm-*` recipes over them.

## What lives where

On the Mac:

| Path | What | Made by |
|---|---|---|
| `/etc/devvm/lima.yaml` | the instance template, generated from both halves | switch |
| `/etc/nix/devvm_ed25519`, `.pub` | the builder identity, root-only; never in the repo or the store | first switch |
| `/etc/nix/devvm_known_hosts` | the guest's host key, pinned under the alias `devvm` | `devvm-adopt` |
| `/etc/nix/machines`, `/etc/ssh/ssh_config.d/101-devvm.conf` | builder registration, and the `Host devvm` alias the daemon's ssh resolves | switch |
| `~/.lima/devvm/` | lima's instance: OS disk, logs, `ssh.config`, and `copied-from-guest/kubeconfig.yaml` while the VM runs | `devvm-up` |
| `~/.lima/_disks/devvm-state/` | the state disk | `devvm-up` |
| `~/code-shared` | the one host directory the guest sees, at the same path on both sides | lima-init at boot; the guest's activation puts it back after every switch |
| `KUBECONFIG`, in every shell | `~/.kube/config` first, the copied kubeconfig second; the tools merge the list | switch |
| `PGHOST`, in every shell | `127.0.0.1`: psql's default is a local socket, and Postgres is in the cluster (D39) | switch |
| `~/code-shared/postgres-dumps/postgres.sql.gz` | the whole of the cluster's Postgres, gzipped, replaced nightly at 02:00; `postgres-dump` makes one now | `org.nixos.postgres-dump` |
| `$TMPDIR/devvm-registry-auth/` | registry credentials that carry an expiry, one file per host, 0600, reused until they expire | the wrappers |
| `~/Library/LaunchAgents/org.nixos.devvm.plist`, `org.nixos.devvm-doctor.plist`, `org.nixos.postgres-dump.plist` | the job that keeps the VM up, the one that checks it, and the nightly dump | switch |
| `~/.local/state/devvm/` | the doctor's last report, and `doctor.log`, one entry per notification | the doctor's job |
| `~/Library/Logs/devvm.log` | what either job prints itself; empty when all is well | launchd |

In the guest:

- The OS disk (60 GiB) is disposable. Every rebuild rewrites it and a
  `limactl delete` throws it away. Its EFI partition is the seed's 249 MiB, and
  GRUB copies a 90 MiB kernel-and-initrd pair onto it per menu entry, so the
  menu lists the current generation only; older generations stay in the store
  for `nixos-rebuild --rollback`.
- The state disk (`devvm-state`; 128 GiB on the work hosts, 40 by default) is mounted at `/var/lib/devvm` and
  holds what should outlive the OS disk: `ssh/` (sshd's host keys and the
  `builder` user's authorized key) and `rancher/`, bind-mounted onto
  `/var/lib/rancher`, which is k3s's data and the single containerd content
  store behind nerdctl, buildkit and the cluster alike; `registry/`, the
  agents' registry, and `buildkit-agents/`, their daemon's own state (D40). A
  builder-only guest keeps `ssh/` and nothing else. The guest formats it
  once, on the first boot of this configuration, and refuses any device that
  already carries a signature.
- Everything else is a NixOS generation.

## Bootstrap, once per machine

Every step has a check, nothing before step 3 changes the guest, and all of it
is reversible ("Removing it", below). On a builder-only host (`personal`) the
share, the shims, the cluster and everything said about them below do not
apply; the four steps are the same, and step 3 has its own form there.

Before starting: Rancher Desktop must not be running. Its k3s forwards 6443 to
localhost exactly as this one will, and the loser gets a TLS error against the
wrong cluster. Docker Desktop can stay — nothing here touches its socket — as
long as `devvm.dockerShims` is off for the host.

1. **Switch.** `just check`, then `just switch`. This generates the builder
   key, writes the template and the ssh alias, and registers a builder that
   does not exist yet. Darwin builds are unaffected: the build hook matches
   system type before it opens ssh. An `aarch64-linux` build fails fast with
   "connection refused" until the VM is up.

       which nerdctl                 # /run/current-system/sw/bin/nerdctl
       which docker                  # unchanged while dockerShims is off
       echo "$KUBECONFIG"            # in a new shell: ~/.kube/config first
       sudo ls -l /etc/nix/devvm_ed25519 /etc/nix/machines

2. **Create and start.** `just devvm-up` creates the state disk and the
   instance (once each; both are idempotent) and starts it. The first start
   downloads the seed image, cached under `~/Library/Caches/lima`. What boots
   is nixos-lima's stock NixOS, not this configuration, and on that boot only,
   `limactl start` ends with `DEGRADED` and a non-zero exit: the template
   tells lima to copy the cluster's kubeconfig out, and the seed has none.
   The instance is running regardless.

       limactl list                  # devvm  Running
       just devvm-shell uname -a     # NixOS, aarch64

3. **First rebuild, from inside.** The seed has flakes on and passwordless
   sudo, but it sees this repo only through the shared directory. Clone the
   committed state there and rebuild from the mount:

       git clone ~/code/tmp/nix-macos-config ~/code-shared/nix-macos-config
       just devvm-shell nixos-rebuild boot --flake /Users/alex/code-shared/nix-macos-config#devvm --sudo
       limactl restart devvm

   `boot` and a restart rather than `switch`: this generation moves sshd's
   keys, adds a user, formats and mounts a disk and starts k3s, and a clean
   boot into it beats a live transition on a foreign generation. The guest
   builds its own system — k3s, nerdctl, buildkit and the kernel are cache
   hits, the airgap image bundle a 216 MiB download. On that boot the state
   disk is formatted, sshd writes its host key onto it, k3s comes up, imports
   the bundled images and publishes its kubeconfig under the name `devvm`, and
   lima copies that out.

       just devvm-status             # instance Running; cluster: node Ready

   `#devvm` is named here because the seed's hostname is not ours. From then
   on the attribute follows the guest's hostname and `just devvm-rebuild`
   needs none. Pushing first and using
   `github:milesAwayAlex/nix-macos-config#devvm` works too; the clone only
   avoids publishing an untested change. It is not needed after this step.

   A builder-only host has no mount, so the Mac drives the same first rebuild
   over lima's ssh — `just devvm-rebuild` with `boot` in place of `switch`,
   and the attribute named because the seed's hostname is not ours:

       NIX_SSHOPTS="-F $HOME/.lima/devvm/ssh.config" nixos-rebuild boot --flake .#devvm-builder --build-host lima-devvm --target-host lima-devvm --sudo
       limactl restart devvm

   The Mac evaluates and ships the derivations; the guest builds and installs
   its own system as before. The seed accepts this because nixos-lima's module
   trusts `wheel` at the nix daemon and gives it passwordless sudo, and
   lima-init puts lima's user in `wheel`.

4. **Adopt.** `just devvm-adopt` reads the guest's host key off the state
   disk and pins it, then pushes the Mac's public key in; sudo prompts once,
   for the pin in `/etc/nix`. It refuses a guest that has not been rebuilt yet
   — that refusal is the check.

5. **Prove the builder.** `just devvm-check` opens the daemon's ssh-ng
   connection and builds a derivation that cannot be substituted. Success is a
   line ending in `aarch64`.

6. **Run a container.** From inside `~/code-shared`:

       nerdctl run --rm -v "$PWD:/w" alpine ls /w

   lists the host directory: path identity working. Then a build the cluster
   can see:

       printf 'FROM alpine\nCMD ["echo", "hello from buildkit"]\n' > Dockerfile
       nerdctl build -t probe .
       kubectx devvm
       kubectl run probe --image=probe --image-pull-policy=Never --restart=Never
       kubectl logs probe

   `nerdctl ps -a` shows the pod's containers next to anything run directly;
   k9s shows only the pod. That asymmetry is by design (PLAN.md Phase 8,
   Visibility).

## Day to day

- **The VM is up from login to logout** (D36). A launchd user agent,
  `org.nixos.devvm`, runs lima's host agent in the foreground: it starts the
  VM at login, starts it again if the host agent dies — 27 seconds from a
  `kill -9` to ready, measured — and shuts the guest down cleanly at logout.
  `just devvm-up` and `just devvm-down` still start and stop it by hand, and
  state survives both, and every rebuild. A stop stays stopped until the next
  `devvm-up` or login; `devvm-up` starts the VM through the same job, so it
  is kept either way.
- **On the work hosts a plugged-in Mac does not sleep while the VM runs**
  (`devvm.keepAwake`, D37): the cluster has work on a schedule, and a
  sleeping Mac freezes the guest. The display still sleeps and locks, on
  battery the Mac sleeps as usual, and `just devvm-down` lets it sleep on AC
  again. `pmset -g assertions` shows the `caffeinate` that holds it.
- **`devvm-doctor` is the first thing to run when anything looks off.** It
  checks the instance, the guest over ssh, every forwarded port, the guest's
  clock, disks, mounts and failed units, and on a cluster the API, the node's
  conditions, the system pods and each `LoadBalancer` and `NodePort` port.
  For each fault it prints what is wrong and the cure from "When it breaks",
  and exits 1; it changes nothing. Pods outside `kube-system` are mentioned
  and never a fault: they are their owner's. launchd runs the same checks
  every two minutes and posts a notification when a fault has held for two
  runs, and one more when it clears, so a boot or a wake is not reported.
  `~/.local/state/devvm/report` is the last run, `doctor.log` beside it one
  entry per notification. `just devvm-status` is the layered view — instance,
  builder, cluster, containerd — for looking rather than judging.
- `just devvm-shell [cmd]` runs in the guest, keeping the working directory
  when it exists on both sides.
- `just devvm-rebuild` deploys a guest change from the Mac: it evaluates here,
  then builds and activates in the guest over lima's own ssh identity, as the
  user lima created. The builder role plays no part, so a guest without it
  deploys the same way. `just devvm-shell nixos-rebuild --rollback switch --sudo`
  is the way back.
- **nerdctl** on the Mac is a wrapper that runs the guest's nerdctl over
  `limactl shell`, as root in the guest. Inside `~/code-shared` it runs in the
  same directory on both sides, so `-v $PWD:/app`, build contexts and compose
  files resolve as they would locally. Anywhere else it runs from an empty,
  read-only directory in the guest: `ps`, `logs`, `pull` and friends work, and
  anything with a relative path fails at once instead of quietly using the
  wrong tree. It forwards your shell environment (lima drops PATH, HOME, SSH_*,
  TERM, XDG_* and the like, the wrapper adds LANG and LC_*, and the rest goes
  through), which is what makes compose's `${VAR}` interpolation work;
  containers see none of it unless passed with `-e`. `docker` and
  `docker-compose` as further wrappers are `devvm.dockerShims`, per host — with
  them on, every `docker` on the machine is nerdctl, so a machine that still
  has Docker Desktop keeps them off. kind works through them and picks its
  nerdctl provider by itself, because `docker -v` answers as nerdctl
  (verified with kind 0.31); `KIND_EXPERIMENTAL_PROVIDER=nerdctl` is the manual
  override, unneeded today. The node container lives in k3s's namespace like
  everything else, so under disk pressure the kubelet may evict its image and
  the next run pulls it again.
- **kubectl, k9s and kubectx** see the cluster as the context `devvm`.
  `KUBECONFIG` is set for every shell to `~/.kube/config` first and the copied
  file second, and the tools merge the list. Nothing is written into
  `~/.kube/config`, gcloud keeps writing there, and the context vanishes with
  the VM: a missing file is skipped, and kubectl fails fast if the current
  context was in it, where a dead 6443 would hang.
- **Ports** in the guest appear on the Mac's `127.0.0.1` under the same
  number, for as long as the VM runs: lima's guest agent reports what it
  finds and the host agent listens for it. It finds two kinds. Anything with
  a listening socket — a `nerdctl run -p`, a `hostNetwork` pod, the API on
  6443 — within three seconds of the bind. And `NodePort` and `LoadBalancer`
  services, which are iptables rules with no socket behind them, through a
  `kubectl` watch: a NodePort under its node port, a LoadBalancer under the
  service's own `port`. A `ClusterIP` service is neither; that is
  `kubectl port-forward`. A port the Mac already uses is skipped with a
  warning in `~/.lima/devvm/ha.stderr.log`, and the listeners are loopback
  only — nothing here is reachable from the network.
- **Postgres and Redis** run in the cluster's `services` namespace (D39), on
  the ports the work code expects, so `localhost:5432` and `:6379` on the Mac
  are lima's forwards of their LoadBalancer services. Postgres 16 with
  PostGIS and pgvector, trust from anywhere, no passwords; `psql` with no
  arguments works through `PGHOST`. From pods, `postgres.services` and
  `redis.services`. Their data is on local-path volumes under the state
  disk, and the volumes outlive the StatefulSets. The images are built by
  this flake and imported by k3s when a guest rebuild links them, a few
  seconds later, so an image change is `just devvm-rebuild` and nothing more.
  `kubectl -n services exec -it postgres-0 -- psql` is a shell on the server.
- **Agents' image builds** (D40) go through a BuildKit daemon of their own,
  `buildkitd-agents`, at `/run/buildkit-agents/buildkitd.sock`; a pod reaches
  it by mounting that directory and joining group 10100. It writes to the
  containerd namespace `agents`, which the cluster never reads, and pushes to
  the registry on the node, `localhost:5050`, from which the cluster pulls:
  a pod names such an image `localhost:5050/NAME:TAG`. Caps: 10 GB of build
  cache, the `agents` namespace's images pruned daily, and the registry's
  tags dropped after a week unpushed, sooner while it is over 15 GiB
  (`agent-builds-prune`, daily). The Mac's own builds keep the other daemon,
  whose cache is capped at 25 GB.
- **The builder** is transparent: any `aarch64-linux` derivation the daemon is
  asked for goes to the guest. `just devvm-check` is the proof when in doubt.
- **Registry credentials** are resolved on the Mac and never stored in the
  guest. `devvm.registryAuth` in the host file names each registry host and a
  command that prints its credential. On every call the wrappers run those
  commands — or reuse an answer whose expiry is still ahead — and hand the
  result to the guest's nerdctl for that call only, through the SSH session
  rather than the command line. In the guest, `docker-credential-devvm` is
  nerdctl's credential store: it answers for the declared hosts and reports
  nothing for the rest, so public registries stay anonymous, and it refuses
  `nerdctl login` with a pointer back here. For `gcr.io` the command is
  gcloud's own helper for external tools, which reports a token *and* its
  expiry and is told to refresh anything with under thirty minutes left, so
  gcloud runs at most twice an hour; `just devvm-status` shows what is cached
  and until when. A long-running nerdctl process, `compose up` say,
  authenticates with what it started with. `just devvm-shell nerdctl …`
  bypasses the wrappers and carries no credentials. The cluster's own pulls
  are a separate path — k3s does not read nerdctl's store — so an image the
  cluster needs from a private registry is pulled with `nerdctl pull` first
  and referenced with `imagePullPolicy: IfNotPresent`; it is the same store
  (D23).

## What a change costs

lima copies `/etc/devvm/lima.yaml` into `~/.lima/devvm/lima.yaml` at creation
and reads *that* file on every start. So a template change after creation is
`just switch` and then, with the instance stopped, copying the regenerated
template over the instance copy (`limactl edit devvm` opens the same file);
the images and the disk sizes are honoured only at creation.

| Change | Where | Then |
|---|---|---|
| Anything in the guest's NixOS config | `modules/nixos/devvm` | `just devvm-rebuild` |
| The lima units themselves, `lima-init` and `lima-guestagent` — the agent's PATH, say | `modules/nixos/devvm` | `just devvm-rebuild`, then `limactl restart devvm`: neither unit restarts at a switch, by design (D22) |
| lima itself (`devvm.package`, set in `flake.nix`) | `flake.lock` | `just switch`; the running host agent is the old lima until `just devvm-down`, `just devvm-up` |
| The launchd job that keeps the VM | `modules/darwin/devvm.nix` | `just switch` reloads a job whose plist changed, and that restarts the VM. The job names `devvm-run` by its profile path so that nothing else — a new lima, a nixpkgs bump — changes the plist |
| Whether the Mac stays awake for the VM (`devvm.keepAwake`) | `hosts/<host>.nix`, or `modules/darwin/work.nix` | `just switch`, then `just devvm-down`, `just devvm-up`: the assertion is taken when the VM starts |
| Which role set this Mac runs (`devvm.guest`) | `hosts/<host>.nix` | `just switch`, then `just devvm-rebuild .#<name>` once — the hostname follows the attribute from there; the template's kubeconfig copy follows the cluster role, so re-sync the instance copy as above |
| A role set that does not exist yet | `flake.nix`, one line | as above |
| CPUs, memory, the shared directory | `hosts/<host>.nix` (`devvm.*`, beside the shims), or `modules/darwin/work.nix` for the work hosts | `just switch`, re-sync the instance copy, start |
| Nested virtualization (`devvm.nestedVirtualization`; M3 and later, off by default) | `hosts/<host>.nix` | a template key: `just switch`, re-sync the instance copy, start. The builder advertises `kvm` either way; without `/dev/kvm` the VM behind such a build runs under TCG |
| A registry host, or how its credential is made | `hosts/<host>.nix` (`devvm.registryAuth`) | `just switch`; a guest from before the credential store needs one `just devvm-rebuild` |
| ssh port | `hosts/<host>.nix` | the same, and both sides before the next start: the daemon's alias and the instance must agree |
| Seed image or `vmType` | `modules/darwin/devvm.nix` | `just devvm-down`, `limactl delete devvm`, then bootstrap steps 2–3 again. The state disk carries both keys, so no adopt, and the cluster comes back |
| `nix flake update nixos-lima` | `flake.lock` | `just devvm-rebuild`; the guest protocol module moves, the seed digest does not, and it only matters at the next creation |
| The state disk's size (`devvm.stateDiskSize`) | `hosts/<host>.nix`, or `modules/darwin/work.nix` for the work hosts | read at creation only. An existing disk grows, never shrinks, by hand: "Growing the state disk", below |
| The state disk itself | — | `limactl disk delete devvm-state` with the instance stopped: new host key and an empty cluster, so `just devvm-adopt` again |

### Growing the state disk

Done once on `work`, 40 to 128 GiB *(2026-11-19)*, with the cluster's data
intact. lima refuses to resize a disk a running instance holds, and grows a
raw one in place; the guest then grows the partition and the filesystem
while it is mounted. The clone is the way back, free on APFS until the two
files diverge; delete it once the cluster has been checked.

    just devvm-down
    /bin/cp -c ~/.lima/_disks/devvm-state/datadisk ~/.local/state/devvm/devvm-state.before-resize.raw
    limactl disk resize devvm-state --size 128GiB
    just devvm-up
    just devvm-shell sudo sfdisk --no-reread --relocate gpt-bak-std /dev/vdb
    echo ', +' | just devvm-shell sudo sfdisk --no-reread -N 1 /dev/vdb
    just devvm-shell sudo partx -u /dev/vdb
    just devvm-shell sudo resize2fs /dev/vdb1

Two `sfdisk` writes, in that order: the backup partition table moves to the
new end of the disk first, and only then is there room for the partition to
grow into — in one command the partition stays the size it was. `/dev/vdb`
is where the disk has been on every boot so far;
`lsblk -no PKNAME /dev/disk/by-label/lima-devvm-state` is the check. Then
set `devvm.stateDiskSize` to match, so the next machine is created that way.

## When it breaks

- **VM-backed builds hang or panic with nested virtualization enabled.**
  On the tested M4/macOS 15.8 setup, concurrent KVM guests can fault with
  `synchronous external abort` before the build script starts (D22).
  Nesting stays off by default; the advertised `kvm` feature still allows
  Nix image builds to use TCG. This is a reliability workaround, not a
  general performance recommendation.

  `just devvm-kvm-check tcg` runs two fresh VM-backed builds with TCG forced.
  To compare real KVM, temporarily expose `/dev/kvm` in the instance. This
  restarts the builder and its containers; it does not change the template:

      limactl stop devvm
      cp ~/.lima/devvm/lima.yaml ~/.lima/devvm/lima.yaml.before-kvm
      sed 's/^nestedVirtualization: false$/nestedVirtualization: true/' ~/.lima/devvm/lima.yaml.before-kvm > ~/.lima/devvm/lima.yaml
      limactl start devvm --tty=false
      just devvm-kvm-check

  The KVM check refuses to fall back to TCG. Repeat it to check intermittent
  failures; each invocation bypasses previously built probe outputs. Both
  modes run two six-vCPU, 1 GiB guests and limit each QEMU run to 120 seconds,
  excluding dependency downloads. Serial logs are included in the build
  output, including when the guest hangs. Restore the normal configuration
  after testing:

      limactl stop devvm
      cp ~/.lima/devvm/lima.yaml.before-kvm ~/.lima/devvm/lima.yaml
      limactl start devvm --tty=false

  Use the saved YAML rather than `limactl edit --nested-virt`: with lima
  2.1.3 that command also replaced newlines in the readiness script with
  literal `#magic___^_^___line` markers during this investigation.

- **Mac build: `nixos-rebuild-ng` fails `test_make_tmpdir`.** The upstream
  test reuses `/tmp/not-too-long` and a fixed long directory without cleaning
  them up. On macOS they survive the build, owned by that build's `nixbld`
  user; another build user cannot write there, so Python ignores the test's
  `TMPDIR`. The host module patches the test to use unique temporary
  directories with cleanup, retaining both path-length checks and the full
  test suite. Remove the override when the pinned nixpkgs fixes the test.
- **`devvm-adopt`: "no host key under /var/lib/devvm/ssh".** The guest is still
  the seed, or the state disk did not mount:
  `just devvm-shell journalctl -u devvm-state-disk -u sshd-keygen` says which.
  sshd's units require the mount, so a key can only be missing there if the
  disk is; a key that turns up on the OS disk instead means a generation from
  before that requirement — `just devvm-rebuild`, `limactl restart devvm`.
- **`devvm-up` ends with `DEGRADED`.** Expected once, on the seed (bootstrap
  step 2). On this configuration it means the kubeconfig copy failed:
  `just devvm-shell journalctl -u k3s -u devvm-kubeconfig`, then
  `limactl restart devvm`.
- **`devvm-rebuild`: "cannot copy … to /boot/kernels/…: No space left on
  device".** The EFI partition is full of kernels from generations the menu
  still lists — a guest from before the one-entry menu — or a half-copied
  `.tmp` from a previous failure. The installer copies the new pair before it
  prunes, so make room by hand once, keeping the running kernel's pair
  (`uname -r`):

      limactl shell devvm sudo sh -c 'ls -la /boot/kernels; rm /boot/kernels/*.tmp'
      limactl shell devvm sudo rm /boot/kernels/<old kernel>-Image /boot/kernels/<its initrd>

  then `just devvm-rebuild` again; from then on the installer keeps the
  partition at two pairs at most.
- **`devvm-rebuild` ends with "Failed to start buildkitd.service" and exit
  code 4, and the unit is fine a few seconds later.** A guest from before
  buildkitd required its containerd unit: activation started the two
  separately, buildkitd dialled a socket k3s had not created yet, and
  `Restart` picked it up afterwards. Nothing is wrong with the switch, which
  was applied; rebuilding onto a configuration with the requirement is the
  fix, and that rebuild is the last one that can show it.
- **`limactl shell` stops working after a rebuild.** `users.mutableUsers` went
  false and the rebuild deleted lima's user. Delete the instance and repeat
  bootstrap steps 2–3; the state disk survives.
- **Builder: "connection refused".** VM stopped. **"Host key verification
  failed".** The guest's host key changed — a new state disk, or the state disk
  failed to mount and sshd generated a fresh key onto the OS disk. The second
  case also shows as an empty cluster; `nofail` lets the guest boot without the
  disk, and this is the loud symptom. **"Permission denied (publickey)".** The
  authorized key is missing or not readable by the `builder` account:
  `just devvm-adopt` puts both right.
- **Builder: "failed to start SSH connection" part-way through a build with
  many derivations, `limactl shell` still fine, a restart cures it until the
  next such build.** The instance copy of the template still forwards ssh
  over vsock — a copy from before `ssh.overVsock = false`. The guest's
  per-connection sshd instances outlive nix's connections and systemd caps
  them at 64; `just devvm-shell systemctl show sshd-vsock.socket -p
  NConnections -p NRefused` shows the count. Re-sync the instance copy as
  under *What a change costs* and start; a restart alone only resets the
  count. Keeping TCP costs little in the measured workload: the M4 Pro
  comparison in D22 found vsock saved about 0.25–0.3 s/GiB downloaded and
  0.9–1 s/GiB uploaded over SSH, with no clear interactive benefit. Virtiofs
  and the guest agent's vsock connection are unaffected. Leave this off until
  upstream fixes cleanup or SSH transfers become a measured bottleneck.
- **kubectl: "context was not found for specified context: devvm".** VM
  stopped, or the kubeconfig probe timed out
  (`just devvm-shell journalctl -u k3s -u devvm-kubeconfig`); `kubectx` to
  another context meanwhile. **"certificate signed by unknown authority".**
  Another cluster owns localhost:6443 — Rancher Desktop — and lima logged a
  failed forward. Stop it, `limactl restart devvm`.
- **A forwarded port takes a connection on the Mac and drops it at once —
  `connection reset by peer`, `EOF`, an empty reply — while the same port
  answers in the guest.** The forwards are stale: the guest agent restarted
  under a running host agent, and lima before 2.3.0 keeps a listener on the
  connection it was created with (lima-vm/lima#5557). Not every restart does
  it and not every port goes: on 2.1.3, the third restart of four left every
  forward dead but the API's *(2026-11-19)*, so kubectl answering proves
  nothing about the rest. `devvm-doctor` lists the ports, and
  `~/.lima/devvm/ha.stderr.log` says `grpc: the client connection is closing`
  once per attempt. ssh rides a forward of its own, so the builder,
  `limactl shell` and the nerdctl wrappers all keep working, which is how
  this goes unnoticed. `limactl restart devvm` is the cure; restarting the
  agent again is not. Two things keep it away. The guest's lima units no
  longer restart at a switch, which is what used to restart the agent; and
  lima here is 2.3.0, taken ahead of the release train for this fix (D36),
  where ten agent restarts in a row left nothing stale. A host agent started
  before that switch is the old lima until the VM is next stopped and
  started.
- **The VM is down and does not come back, or keeps restarting.**
  `launchctl print gui/$(id -u)/org.nixos.devvm` shows the job's state, its
  last exit code and how often it has run; `~/Library/Logs/devvm.log` has
  what the job printed before the host agent took over, and
  `~/.lima/devvm/ha.stderr.log` the rest. A clean exit is never answered: a
  VM stopped with `devvm-down`, or one that shut itself down, waits for
  `just devvm-up`. launchd starts a failing job again every 30 seconds.
- **`devvm-doctor`: "started by hand, so launchd is not keeping it".** The
  host agent is not the job's process — the VM was up before the job was
  loaded, or was started with `limactl start`. `just devvm-down`, then
  `just devvm-up`.
- **A `LoadBalancer` or `NodePort` service answers in the guest and not on
  the Mac.** The guest agent has no `kubectl` to watch services with: a
  generation from before k3s's was on its PATH, or one since, not yet
  restarted into — `just devvm-rebuild`, `limactl restart devvm`. The check
  is the watch itself, a `kubectl` process the agent keeps running:
  `just devvm-shell pgrep -a kubectl` (by name — k3s's multicall binary
  blanks its arguments). With the watch running, look
  for the port in `ha.stderr.log`: `Forwarding TCP` when it worked,
  `failed to listen` when the Mac already had that port. lima does not
  retry that bind once the Mac frees the port, and restarting the guest
  agent does not make it: the port never left the guest. Delete and
  recreate the Service (`kubectl get svc NAME -o yaml`, delete, apply), or
  restart the VM; seen at the Postgres cutover (D39).
- **A pull is refused with `401` or "unauthorized".** The registry is not in
  `devvm.registryAuth`, or its command failed — the wrapper says so on stderr
  before nerdctl runs, and for gcr.io that is usually `gcloud auth login`
  being due. After switching gcloud accounts the cached answer stays until it
  expires: `rm -r "$TMPDIR/devvm-registry-auth"`. If the command works and the
  pull still fails, the variable is not arriving: either the guest predates the
  credential store and its sshd does not accept it (`just devvm-rebuild`), or
  lima's persistent ssh connection predates the rebuild that taught sshd to —
  every `limactl shell` multiplexes over one control master, and the sshd
  child serving it keeps the config it started with. Drop it, and lima opens a
  fresh one on the next call:

      ssh -F ~/.lima/devvm/ssh.config -O exit lima-devvm

  This closes every session riding on it, an open `just devvm-shell` included.
- **The share is empty in the guest.** `ls ~/code-shared` lists files on the
  Mac, `devvm-status` says `NOT mounted`, and a wrapper run from inside it
  fails with `cd: … No such file or directory`. A guest generation from before
  the activation remount: lima-init mounts the share through `/etc/fstab`,
  which every switch regenerates and prunes, so it lived from boot until the
  first rebuild. `just devvm-shell sudo systemctl restart lima-init` puts it
  back now; a rebuild onto this configuration is the last one that can lose
  it.
- **`nerdctl login` fails with "registry logins live on the Mac".** By design:
  declare the host in `devvm.registryAuth` instead.
- **`docker` behaves like nerdctl.** The shims are on for this host.
- **A relative path fails outside `~/code-shared`.** By design: the wrapper
  runs from an empty directory there. An absolute Mac path outside it gives an
  empty volume instead — bind mounts resolve in the guest, and root there
  creates the missing directory.
- **The guest's disk fills.** The kubelet garbage-collects the shared content
  store from 95 % down to 90 %, oldest images first, and an image built with
  nerdctl that no pod runs is fair game. `nerdctl system prune` is aimed at the
  cluster's images too (same namespace); prefer `nerdctl image rm` by name, or
  `crictl rmi --prune` for what the kubelet would take anyway.

## Removing it

`devvm.enable = false` and `just switch` drops the builder registration, the
ssh alias, the template, the tools and both launchd jobs — and a VM the job
was keeping stops with it. Then, if the VM should go too:

    limactl delete -f devvm
    limactl disk delete devvm-state
    sudo rm /etc/nix/devvm_ed25519 /etc/nix/devvm_ed25519.pub /etc/nix/devvm_known_hosts

The key files are deliberately left alone by the switch: they are machine
state, and regenerating them costs an adopt.
