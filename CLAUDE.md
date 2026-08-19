# CLAUDE.md

Declarative macOS machine configuration: flake-based nix-darwin + home-manager (module mode). **Public repo — no secret ever enters the repo or the Nix store**, in any form.

## Read first

- `PLAN.md` — principles, settled stack decisions, phased roadmap, current status. The durable _why_.
- `DECISIONS.md` — operating conventions, ADR-lite (D1–…). The durable _how_. **New conventions get an entry there** — not code comments, not PLAN.md.

## Workflow

- `just switch` / `build` / `check` / `update [input]` / `gc`. Host resolved via `NIXHOST` (default `work`). Rebuilds are deliberate events; sudo password prompts are expected (no Touch ID, no NOPASSWD on `work`).
- Flakes cannot see untracked files — `git add` new files before any flake command, or the eval fails confusingly.
- The gitleaks pre-commit hook is versioned in `.githooks/` and activates automatically on HM-configured machines via the `hasconfig` include in `modules/home/git.nix` (D7/D9); on machines without this HM config, activate per clone: `git config core.hooksPath .githooks`.

## Repo-specific gotchas

- `modules/home/karabiner/karabiner.json` is canonical. The live file at `~/.config/karabiner/karabiner.json` is converge-copied on switch — never edit the live file; edits are silently overwritten (D2). The same file is also copied to Karabiner's pre-login path by `modules/darwin/input`, so login-window typing depends on it.
- Inputs are a matched 26.05 release-train set (nixpkgs-26.05-darwin + nix-darwin-26.05 + home-manager release-26.05) — bump all three together, never individually (D6).
- The personal machine (`old`) consumes `homeModules.karabiner` (and optionally `darwinModules.input`) as a flake input; changes here reach it only via a deliberate `nix flake update nix-macos-config` there.
