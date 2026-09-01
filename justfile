host := env("NIXHOST", "work")

# list recipes
default:
    @just --list

# apply the configuration
switch:
    sudo darwin-rebuild switch --flake .#{{host}}

# build without activating (no sudo); leaves ./result
build:
    darwin-rebuild build --flake .#{{host}}

# fast eval sanity check (no build)
check:
    nix eval .#darwinConfigurations.{{host}}.system.drvPath

# bump the lock file (optionally a single input: `just update nixpkgs`)
update *input:
    nix flake update {{input}}

# collect garbage, matching the automatic policy — never bare -d
gc:
    sudo nix-collect-garbage --delete-older-than 14d

# format nix code (nixfmt via treefmt, wired as the flake formatter)
fmt:
    nix fmt

# hand DNS back to DHCP: captive portals, or a dead resolver stack.
# `just switch` puts it back, as does a reboot of the daemons.
dns-dhcp svc="Wi-Fi":
    sudo networksetup -setdnsservers "{{svc}}" empty

# point DNS back at the local stack without a full rebuild
dns-local svc="Wi-Fi":
    sudo networksetup -setdnsservers "{{svc}}" 127.0.0.1

# show the DNS picture end to end: persisted, live, effective, and each hop.
# The persisted/live split matters — a switch made while the VPN owns DNS
# writes the file but never reaches configd, so the stack runs unused.
dns-status:
    #!/usr/bin/env bash
    echo "── persisted (preferences.plist — what networksetup reports)"
    for s in "Wi-Fi" "Thunderbolt Bridge" "USB 10/100/1000 LAN" "USB 10/100/1G/2.5G LAN"; do
        printf "   %-24s %s\n" "$s" "$(networksetup -getdnsservers "$s" 2>&1 | tr '\n' ' ')"
    done
    echo "── live (configd Setup store — a service absent here is NOT applied)"
    echo 'list Setup:/Network/Service/.*/DNS' | scutil | sed 's/^ */   /'
    echo "── effective"
    scutil --dns | sed -n '/^resolver #1/,/^$/p' | sed 's/^/   /'
    echo "── hops"
    for hop in 53:dnsmasq 5300:blocky 5335:unbound; do
        port="${hop%%:*}"; name="${hop#*:}"
        if dig @127.0.0.1 -p "$port" example.com +short +time=2 +tries=1 >/dev/null 2>&1; then r=ok; else r=FAIL; fi
        printf "   %-8s :%-5s %s\n" "$name" "$port" "$r"
    done
    if dig @127.0.0.1 ads.google.com +time=2 +tries=1 2>/dev/null | grep -q NXDOMAIN; then
        echo "   blocking       engaged"
    else
        echo "   blocking       NOT engaged"
    fi

# the tool is built by modules/darwin/preferences.nix and lands on PATH at
# switch, so it always checks against the generation that is running. Kept here
# because `just --list` is where this repo's operations are indexed.
# read every declared preference back out of its real domain; non-zero on drift
prefs-status:
    prefs-status

# ── dev VM: builder, cluster, containers (PLAN.md Phase 8) ───────────────────

# create the state disk and the VM from the configuration, and start it. A new
# instance boots the seed image, not this configuration: the first rebuild and
# the key exchange follow (DEVVM.md, "Bootstrap")
devvm-up:
    devvm-up

# stop the VM. State survives; the kubeconfig is deleted on stop by design,
# so kubectl fails fast instead of hanging on a dead 6443.
devvm-down:
    limactl stop devvm

# layered view: instance, builder, cluster, containerd
devvm-status:
    devvm-status

# push the host's public key in and pin the guest's host key. Once per state
# disk, after the first rebuild has put that disk in place. Idempotent, and the
# one step that cannot be declarative: neither key exists at build time.
devvm-adopt:
    sudo /run/current-system/sw/bin/devvm-adopt

# a shell in the guest, keeping the working directory
devvm-shell *args:
    limactl shell devvm {{ args }}

# rebuild the guest from this checkout: the Mac evaluates, the guest builds and
# activates its own system, reached over lima's ssh identity as lima's user
# (wheel, passwordless sudo). The `builder` account is a normal user by design
# and cannot activate; the builder role is not involved at all. No attribute:
# nixos-rebuild asks the guest for its hostname, which is the attribute it
# runs. Changing role sets names the new one once: `just devvm-rebuild .#devvm-builder`
devvm-rebuild flake=".":
    NIX_SSHOPTS="-F $HOME/.lima/devvm/ssh.config" nixos-rebuild switch --flake {{ flake }} --build-host lima-devvm --target-host lima-devvm --sudo

# prove the builder end to end with a derivation that cannot be substituted
devvm-check:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo nix store info --store ssh-ng://devvm
    out=$(nix build --no-link --print-out-paths --impure --expr \
        'let p = (builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.aarch64-linux;
         in p.runCommand "devvm-probe" { } "uname -srm > $out"')
    echo "built on: $(cat "$out")"
