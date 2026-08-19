# nix-macos-config

Declarative macOS machine configuration: flake-based nix-darwin + home-manager,
public from day one. The durable record of architecture decisions and the phased
roadmap lives in [PLAN.md](PLAN.md); operating conventions in
[DECISIONS.md](DECISIONS.md); the Karabiner chord cheatsheet in
[KEYBOARD.md](KEYBOARD.md).

## Seed record

| | |
|---|---|
| Installer | [NixOS/nix-installer](https://github.com/NixOS/nix-installer) 2.35.1 |
| Nix | 2.35.1 (upstream CppNix) |
| Installed | 2026-08-15, on `work` |
| Receipt | `/nix/receipt.json` |
| Uninstall | `sudo /nix/nix-installer uninstall` |

After the first `darwin-rebuild switch`, nix-darwin (`nix.package`) owns the
running Nix; the installer's remaining job is the uninstall receipt.

## Workflow

Day-to-day operations are `just` recipes; the host is selected via `NIXHOST`
(default `work`):

    just switch   # apply the configuration (sudo)
    just build    # build without activating; leaves ./result
    just check    # fast eval sanity check
    just update   # bump flake.lock (or one input: `just update nixpkgs`)
    just gc       # collect garbage per the 14d policy

## Per-clone setup

Hooks are versioned in `.githooks/`. On a machine running this repo's
home-manager config, they activate automatically — the managed git config
recognizes any clone of this repo by its remote URL and sets
`core.hooksPath` (D7/D9). Elsewhere, enable them once per clone:

    git config core.hooksPath .githooks

The pre-commit hook runs gitleaks against staged changes and refuses commits
containing secrets. It is the seatbelt, not the strategy: no secret ever enters
this repo or the Nix store (PLAN.md, principle 5).

## Per-machine manual steps

After the first successful `just switch` on a new machine:

    chsh -s /run/current-system/sw/bin/bash

The switch itself registers nix bash in `/etc/shells`
(`environment.shells`); the flip is the one step nix-darwin doesn't do for
us. If `/run` is ever broken, `/bin/bash` remains the rescue shell.

## Consuming modules from another flake

Portable home modules are exported as `homeModules.*`, so a machine not
yet ported into this repo can reuse them:

    # flake.nix
    inputs.nix-macos-config.url = "github:milesAwayAlex/nix-macos-config";

    # anywhere in that flake's home-manager configuration
    imports = [ inputs.nix-macos-config.homeModules.karabiner ];

The karabiner module converges `~/.config/karabiner/karabiner.json` on
activation (a copy, not a symlink — Karabiner mishandles symlinked config);
local edits to the live file are overwritten on every switch. Updates are
deliberate pulls: `nix flake update nix-macos-config`, then rebuild.
