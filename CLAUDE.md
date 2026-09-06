# CLAUDE.md

Declarative macOS machine configuration: flake-based nix-darwin + home-manager (module mode). **Public repo — no secret ever enters the repo or the Nix store**, in any form.

## Read first

- `PLAN.md` — principles, settled stack decisions, phased roadmap, current status. The durable _why_.
- `DECISIONS.md` — operating conventions, ADR-lite (D1–…). The durable _how_. **New conventions get an entry there** — not code comments, not PLAN.md.
  Comments say why the code is the way it is *now*; history, dated notes and
  rejected alternatives belong in PLAN/DECISIONS.

## Workflow

- `just switch` / `build` / `check` / `update [input]` / `gc`. Host resolved via `NIXHOST` (default `work`). Rebuilds are deliberate events; sudo authenticates by Touch ID (`modules/darwin/pam.nix`), falling back to the password prompt; NOPASSWD never will be.
- Flakes cannot see untracked files — `git add` new files before any flake command, or the eval fails confusingly.
- The gitleaks pre-commit hook is versioned in `.githooks/` and activates automatically on HM-configured machines via the `hasconfig` include in `modules/home/git.nix` (D7/D9); on machines without this HM config, activate per clone: `git config core.hooksPath .githooks`.

## Repo-specific gotchas

- `modules/home/karabiner/karabiner.json` is canonical. The live file at `~/.config/karabiner/karabiner.json` is converge-copied on switch — never edit the live file; edits are silently overwritten (D2). The same file is also copied to Karabiner's pre-login path by `modules/darwin/input`, so login-window typing depends on it.
- Inputs are a matched 26.05 release-train set (nixpkgs-26.05-darwin + nix-darwin-26.05 + home-manager release-26.05) — bump all three together, never individually (D6).
- A **placeholder `hash`** in a `fetchFromGitHub`/`fetchurl` fails here with a
  TLS error rather than a hash mismatch. Get the real hash out of band
  (`nix hash path` on an extracted tree); the network is not the problem.
- Homebrew is the appliance tier: **casks only, and only casks that
  self-update** (D16). Two bites. `cleanup` is off, so deleting a line here
  does not remove the app from a machine that already has it. And
  `brew install --cask` *aborts* if the app already exists at its
  `/Applications` path and brew did not put it there — during activation that
  fails the switch, so adopt first: `brew install --cask --adopt <name>`.
- Homebrew itself is nix-managed: nix-homebrew clones `Homebrew/brew` from a
  flake input, so brew's version is pinned in `flake.lock` and `brew update`
  is not how it moves — `nix flake update nix-homebrew` is.
- Unfree packages need their name in the `allowUnfreePredicate` list in
  `hosts/work.nix` (D18). It cannot go in a home module: `useGlobalPkgs = true`
  drops home-manager's `nixpkgs.*` module outright, so `nixpkgs.config` is not
  an option that exists there. Employer-coupled home modules are imported from
  the same host file for the same reason — `home-manager.users.alexm.imports`
  merges cleanly with the assignment in `flake.nix` (verified).
- `system.defaults` is write-only (`modules/darwin/preferences.nix`): one
  `defaults write` per key at activation, never read back, so removing a key
  stops the write but leaves the value on the machine, and nothing is enforced
  between switches — a revert means setting the opposite value. `prefs-status`
  reads every declared key back and reports drift, and an eval-time assertion
  checks the module's domain map against the writes nix-darwin actually emits,
  so a stale map fails `just check` rather than letting the tool go quietly
  blind. **PREFERENCES.md is the operating manual** — adding keys, removing
  them, what needs a restart, crossing a nix-darwin version. Read it before
  touching this module.
- The dev VM (D22/D23) is a lima instance, `devvm`, whose guest is one of two
  role sets the flake exports as `nixosConfigurations` — `devvm` (builder,
  containers, cluster) and `devvm-builder`. A Mac names the one it runs in
  `devvm.guest` in its host file and declares sizing, the shared directory and
  its shims beside it; the darwin module reads everything else from the guest.
  **DEVVM.md is the operating manual** — bootstrap order, day-to-day recipes,
  what each kind of change costs; read it before touching either half. Three
  things bite: `users.mutableUsers = true` in the
  guest is **mandatory** (lima creates its user imperatively; a rebuild without
  it deletes that user and your `limactl shell` access),
  `services.openssh.authorizedKeysFiles` must be added to rather than replaced
  (the default entry is where lima writes its own key), and `just devvm-adopt`
  is the one non-declarative step — it exchanges the two public keys that only
  exist at runtime, and only after the first rebuild has put the state disk in
  place. The seed image digest in `modules/darwin/devvm.nix` is read once at
  instance creation and does **not** move when `nix flake update nixos-lima`
  runs. Registry credentials are resolved on the Mac (`devvm.registryAuth`)
  and delivered to the guest per call; `nerdctl login` in the guest is refused
  by design.
- The personal machine (`old`) consumes `homeModules.karabiner` (and optionally `darwinModules.input`) as a flake input; changes here reach it only via a deliberate `nix flake update nix-macos-config` there.
