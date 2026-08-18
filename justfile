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
