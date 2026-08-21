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
