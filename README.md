# nix-macos-config

Declarative macOS machine configuration: flake-based nix-darwin + home-manager,
public from day one. The durable record of architecture decisions and the phased
roadmap lives in [PLAN.md](PLAN.md).

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

## Per-clone setup

Hooks are versioned in `.githooks/`, but git never auto-activates hooks from a
clone. Enable them once per clone:

    git config core.hooksPath .githooks

The pre-commit hook runs gitleaks against staged changes and refuses commits
containing secrets. It is the seatbelt, not the strategy: no secret ever enters
this repo or the Nix store (PLAN.md, principle 5).
