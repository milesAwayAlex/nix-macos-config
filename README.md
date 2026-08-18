# nix-macos-config

Declarative macOS machine configuration: flake-based nix-darwin + home-manager,
public from day one. The durable record of architecture decisions and the phased
roadmap lives in [PLAN.md](PLAN.md); operating conventions in
[DECISIONS.md](DECISIONS.md); the Karabiner chord cheatsheet in
[KEYBOARD.md](KEYBOARD.md).

## Status

Phase 1 (seed + skeleton) in progress on `work`. Nothing here configures a
machine yet.

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

Hooks are versioned in `.githooks/`, but git never auto-activates hooks from a
clone. Enable them once per clone:

    git config core.hooksPath .githooks

The pre-commit hook runs gitleaks against staged changes and refuses commits
containing secrets. It is the seatbelt, not the strategy: no secret ever enters
this repo or the Nix store (PLAN.md, principle 5).

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
