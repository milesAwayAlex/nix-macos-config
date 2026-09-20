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
| `$TMPDIR/devvm-registry-auth/` | registry credentials that carry an expiry, one file per host, 0600, reused until they expire | the wrappers |

In the guest:

- The OS disk (60 GiB) is disposable. Every rebuild rewrites it and a
  `limactl delete` throws it away. Its EFI partition is the seed's 249 MiB, and
  GRUB copies a 90 MiB kernel-and-initrd pair onto it per menu entry, so the
  menu lists the current generation only; older generations stay in the store
  for `nixos-rebuild --rollback`.
- The state disk (`devvm-state`, 40 GiB) is mounted at `/var/lib/devvm` and
  holds what should outlive the OS disk: `ssh/` (sshd's host keys and the
  `builder` user's authorized key) and `rancher/`, bind-mounted onto
  `/var/lib/rancher`, which is k3s's data and the single containerd content
  store behind nerdctl, buildkit and the cluster alike; a builder-only guest
  keeps `ssh/` and nothing else. The guest formats it
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
       just devvm-shell nixos-rebuild boot --flake /Users/alexm/code-shared/nix-macos-config#devvm --sudo
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

- `just devvm-up` and `just devvm-down` start and stop. State survives both,
  and every rebuild. `just devvm-status` is the layered view — instance,
  builder, cluster, containerd — and the first thing to run when anything
  looks off. `just devvm-shell [cmd]` runs in the guest, keeping the working
  directory when it exists on both sides.
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
| Which role set this Mac runs (`devvm.guest`) | `hosts/<host>.nix` | `just switch`, then `just devvm-rebuild .#<name>` once — the hostname follows the attribute from there; the template's kubeconfig copy follows the cluster role, so re-sync the instance copy as above |
| A role set that does not exist yet | `flake.nix`, one line | as above |
| CPUs, memory, the shared directory | `hosts/<host>.nix` (`devvm.*`, beside the shims) | `just switch`, re-sync the instance copy, start |
| Nested virtualization (`devvm.nestedVirtualization`; M3 and later, on by default) | `hosts/<host>.nix` | a template key: `just switch`, re-sync the instance copy, start. The builder's `kvm` feature follows it at the switch, and only a guest with `/dev/kvm` can honour it |
| A registry host, or how its credential is made | `hosts/<host>.nix` (`devvm.registryAuth`) | `just switch`; a guest from before the credential store needs one `just devvm-rebuild` |
| ssh port | `hosts/<host>.nix` | the same, and both sides before the next start: the daemon's alias and the instance must agree |
| Seed image or `vmType` | `modules/darwin/devvm.nix` | `just devvm-down`, `limactl delete devvm`, then bootstrap steps 2–3 again. The state disk carries both keys, so no adopt, and the cluster comes back |
| `nix flake update nixos-lima` | `flake.lock` | `just devvm-rebuild`; the guest protocol module moves, the seed digest does not, and it only matters at the next creation |
| The state disk itself | — | `limactl disk delete devvm-state` with the instance stopped: new host key and an empty cluster, so `just devvm-adopt` again |

## When it breaks

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
  count.
- **kubectl: "context was not found for specified context: devvm".** VM
  stopped, or the kubeconfig probe timed out
  (`just devvm-shell journalctl -u k3s -u devvm-kubeconfig`); `kubectx` to
  another context meanwhile. **"certificate signed by unknown authority".**
  Another cluster owns localhost:6443 — Rancher Desktop — and lima logged a
  failed forward. Stop it, `limactl restart devvm`.
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
ssh alias, the template and the tools. Then, if the VM should go too:

    limactl delete -f devvm
    limactl disk delete devvm-state
    sudo rm /etc/nix/devvm_ed25519 /etc/nix/devvm_ed25519.pub /etc/nix/devvm_known_hosts

The key files are deliberately left alone by the switch: they are machine
state, and regenerating them costs an adopt.
