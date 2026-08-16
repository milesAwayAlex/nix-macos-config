# Declarable Machine Config — Transition Plan

Configuration-as-code for macOS (and beyond): portable, reviewable, reproducible.
This document is the durable record of the architecture decisions and the phased
transition plan. The repo this plan produces is **public from day one**.

## Principles

1. **One declarative surface.** nix-darwin is the authority; everything else
   (homebrew, home-manager, defaults) hangs off it. Avoid second config systems.
2. **Reviewable beats clever.** Plain artifacts where they're clearer; Nix where
   integration pays. Preference order: HM module → system-wide nix → plain file,
   pragmatically, erring toward Nix; retreat to plain when ergonomics demand.
3. **Match update model to the software.** Pinned-and-reproducible for tools;
   self-updating "appliance tier" for security-critical and fast-moving apps
   (browsers, password managers, AI harnesses). The repo declares *presence*;
   the vendor owns *version*. This is a decision, not an omission.
4. **Graceful abandonment.** Every layer degrades without rewrite: casks → Brewfile,
   linked dotfiles → plain dotfiles, keylayout → manual install. Nothing is hostage.
5. **Host is the security boundary.** No secret ever enters the Nix store or the
   repo. VMs get forwarded/ephemeral credentials, never stored ones.

## Stack decisions (settled)

| Layer | Choice | Key rationale |
|---|---|---|
| Installer (seed) | [NixOS/nix-installer](https://github.com/NixOS/nix-installer) (the community fork, graduated from `experimental-nix-installer`; pinned 2.35.1) | Determinate-installer ergonomics (receipt uninstall, macOS-upgrade survival), installs upstream Nix, distributed from `artifacts.nixos.org`. Since 2026-01 the DetSys installer installs Determinate Nix *only*, so this fork is the sole receipt-style path to upstream Nix. Seed only — see below. |
| Interpreter | Upstream CppNix, via `nix.enable = true` + `nix.package` | nix-darwin manages Nix itself; upgrades ride the rebuild train. Lix = one-line `nix.package` flip later. Determinate Nix rejected for now: proprietary nixd + `nix.*` carve-outs vs. our single-surface principle. |
| System config | nix-darwin (flake-based) | `system.defaults`, launchd, activation scripts, homebrew driver. |
| User config | home-manager **as nix-darwin module** | One command, one lock, one GC, atomic generations. Flip to standalone per-machine only if no-Touch-ID password friction grates (work machine candidate). |
| nixpkgs | **26.05 release train**: `nixpkgs-26.05-darwin` + matched `nix-darwin-26.05` + HM `release-26.05`; weekly lock bumps via `update-flake-lock` action | Flipped from unstable 2026-08-15, pre-payload ("zero to unstable felt iffy"). Darwin-tested stable channel; train bump = twice-yearly deliberate chore (26.11 due ~Nov 2026; 26.05 EOL ~Dec 2026). Escape hatches: flip to unstable (3 input lines) if a forced macOS update needs master-only fixes; surgical secondary unstable input if package freshness hurts (Phase 4). |
| GUI apps | Homebrew casks via nix-darwin + **nix-homebrew** (taps pinned as flake inputs, `autoMigrate` adopts existing install) | Casks for self-updating/permission-heavy apps; nixpkgs + mac-app-util for stable dev GUI (Alacritty). |
| Spotlight/Dock fix | mac-app-util module | Trampolines fix Spotlight indexing, Dock pins, TCC churn for nix-installed .apps. |
| Secrets | 1Password-first runtime references (`op`, SSH agent); **nothing in repo/store**; sops-nix deferred until first server/VM | gitleaks pre-commit as seatbelt. Bitwarden = second domain; vaultwarden self-host option later. |
| Browsers | **Both first-class.** Chrome: cask + declared policy baseline (G Suite daily driver). Firefox: cask app + full `programs.firefox` config (profile, user.js, NUR extensions). | Both self-update (appliance tier). Never install browsers from nixpkgs on macOS. |
| AI harnesses | Native self-updating installers, bootstrapped by activation script; configs (`~/.claude/settings.json` etc.) HM-linked per-file | Binary = appliance; config = code. |
| GC | `nix.gc.automatic`, `--delete-older-than 14d`, `nix.optimise.automatic` | Never bare `-d`. Module-mode HM = single profile chain. |
| Shell | **bash** (modern bash 5 from nixpkgs as login shell; macOS ships 3.2) | `programs.bash` in HM; `/etc/shells` via `environment.shells`; one manual `chsh`. |
| Editor | **vim** (`programs.vim`, plugins from `pkgs.vimPlugins`, large vimrc sourced as plain file) | Case-by-case escape hatch per principle 2. |
| Sudo ergonomics | Work machine: no Touch ID, no NOPASSWD (≈ passwordless root; unacceptable on managed hardware). Personal/old machine: `security.pam.services.sudo_local.touchIdAuth = true`. | Rebuilds are deliberate, infrequent events; browser security does NOT depend on rebuild cadence. |

## Machines

| Alias | Hardware | Status |
|---|---|---|
| `work` | This laptop, macOS 15.7.7 (Sequoia), **MDM-managed**, no Touch ID, Homebrew present | First target. Phase 0 MDM gate passed; Nix seeded 2026-08-15. |
| `old` | Old laptop (personal), running its own flake-based nix-darwin + HM config | Host #2. Near-term: its flake consumes this repo as an input (`homeManagerModules.*`) for shared modules (karabiner first). Full port into this repo = Phase 6. |

Flake outputs are **alias-named** (`darwinConfigurations.work`, `.old`);
`darwin-rebuild switch --flake ~/dotfiles#work` — hostname lookup is only a default.
The justfile resolves the alias (env var `NIXHOST` or `hostname -s` mapping).

---

## Phase 0 — Preflight (MDM gate) — **GATE PASSED 2026-06-12** ☑

- [x] **MDM/endpoint check:** Kandji (Iru) MDM, DEP-enrolled, User Approved.
      Endpoint stack: SentinelOne EDR (ESF + network ext), Kandji ESF, Jamf
      Protect, Perimeter 81 VPN, Vanta compliance agent.
      **No application allowlisting observed** (no Santa/binary authorization);
      Homebrew already present and user-owned (`/opt/homebrew`, alexm:admin);
      user is admin with sudo (password, no Touch ID).
      Karabiner DriverKit extension (v1.8) **already approved and active** —
      extension-approval path proven on this MDM, and Phase 2's manual grants
      are already done on this machine.
      TLS to `cache.nixos.org` terminates at Let's Encrypt — **no SSL
      inspection**; binary cache will work. FileVault on; WG-fork installer
      creates the store volume encrypted under FileVault → Vanta-safe.
      No existing nix / synthetic.conf. macOS 15.7.7 (24G720).
      **Residual risks:** (1) SentinelOne/Jamf heuristics may throttle or kill
      large local builds (mass process-spawn + /nix writes) — fix is an IT
      exclusion for `/nix` + nix daemon; watch for it, mostly we substitute from
      cache anyway. (2) Courtesy heads-up to IT before install is cheap
      insurance on a managed device. (3) Kandji may *force* macOS updates on
      IT's schedule — inverts our "never day-one" policy, so keep the lock file
      current enough that post-macOS-update nix-darwin fixes are available.
- [ ] `chrome://management` — note what's already centrally managed (manual,
      in-browser).
- [ ] Inventory into repo as raw material: `brew bundle dump`, `ls /Applications`,
      current dotfiles (`.bashrc`, `.vimrc`, `.tmux.conf`, karabiner.json, ssh config),
      interesting `defaults` domains, any existing nix.
- [ ] Time Machine snapshot. *(Skipped ahead of the Nix seed — installer is
      receipt-reversible; still wanted before Phase 2 root activation.)*
- [x] Create **public** GitHub repo: **`nix-macos-config`** (this repo) — plan +
      README recording decisions, gitleaks pre-commit hook from commit one, MIT
      license. *(2026-08-15)*

**Gate:** MDM verdict positive; inventory committed.

## Phase 1 — Seed + skeleton ☐

- [x] Install via [NixOS/nix-installer](https://github.com/NixOS/nix-installer)
      **2.35.1** → Nix 2.35.1, *2026-08-15*. Receipt: `/nix/receipt.json`;
      uninstall: `sudo /nix/nix-installer uninstall`. Recorded in README.
      *(Installer run from a locally reviewed copy of the bootstrap script —
      it pins the release itself.)*
- [ ] Flake skeleton:
  ```nix
  # flake.nix (sketch)
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin";
    home-manager.url = "github:nix-community/home-manager";
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    mac-app-util.url = "github:hraban/mac-app-util";
    # later: nur (firefox addons)
  };
  ```
  Module layout: `modules/darwin/` (system), `modules/home/` (portable),
  `hosts/work.nix`, `hosts/old.nix`. Portable home modules also exported as
  `homeManagerModules.*` flake outputs so the `old` machine's existing flake
  can consume them before its Phase 6 port.
- [ ] Core nix settings: `nix.enable = true`; `nix.gc.automatic = true` with
      `--delete-older-than 14d`; `nix.optimise.automatic = true`;
      `nix.settings.experimental-features = [ "nix-command" "flakes" ]`;
      `system.stateVersion`.
- [ ] Wire home-manager module + mac-app-util; HM config near-empty for now —
      first payload: karabiner.json (pulled forward from Phase 2).
- [ ] `justfile`: `switch`, `update`, `gc`, `check` targets. `CLAUDE.md` documenting
      the workflow. `update-flake-lock` GitHub Action (weekly PR).
- [ ] First `sudo darwin-rebuild switch --flake .#work`.

**Gate:** second switch is a no-op (idempotent); `nix.package` owns the running Nix;
bot PR pipeline works.

## Phase 2 — Input layer: Programmer Dvorak + Karabiner ☐

Goal: both active **at the login window** (FileVault pre-boot stays QWERTY — EFI,
unavoidable; type that password in QWERTY).

- [ ] Vendor `ProgrammerDvorak.keylayout` XML in repo (extract from Kaufmann pkg or
      community copy; it's reviewable XML). TODO: pick exact variant.
- [ ] System-wide install via root activation:
  ```nix
  system.activationScripts.postActivation.text = ''
    cp -f ${./keyboard/ProgrammerDvorak.keylayout} \
      "/Library/Keyboard Layouts/ProgrammerDvorak.keylayout"
  '';
  ```
- [ ] Login-window input menu declaratively
      (`/Library/Preferences/com.apple.loginwindow showInputMenu = true` —
      via `system.defaults` or `CustomSystemPreferences`; verify exact key).
- [ ] Karabiner-Elements app: currently a manually-installed bundle (brew cask was
      broken at install time) — adopt as cask in Phase 3 (`--force`/adopt moment;
      recheck whether the cask works).
- [ ] Config delivery: **undecided — Karabiner is known finicky with symlinked
      config; test before committing to a mechanism.** Candidates: store-symlink
      the whole dir (`xdg.configFile."karabiner"`) · symlink only
      `karabiner/karabiner.json` (Karabiner writes `automatic_backups/` beside
      it at runtime) · HM activation copies a plain writable file · generate
      from a Nix attrset via `builtins.toJSON`. Whatever wins: per-machine
      device blocks can ship as the union of both machines' devices (entries
      for absent devices are inert); the symlink options sacrifice GUI editing.
- [ ] Pre-login remapping: activation step copying karabiner.json to Karabiner's
      *system default configuration* path (automates the documented
      "use before logging in" GUI button; verify path during implementation).
- [ ] Manual (checklist): approve system extension + Input Monitoring; enable
      input source in System Settings; log out/in.

**Gate:** layout selectable and Karabiner remapping live at the login window;
both survive reboot; `darwin-rebuild` after a keylayout/karabiner edit converges.

## Phase 3 — App layer: casks, browsers, password managers ☐

- [ ] nix-homebrew with `autoMigrate = true` (adopts existing brew; future machines
      bootstrap from nothing); Homebrew/tap repos pinned as flake inputs.
- [ ] Casks (appliance tier unless noted): `karabiner-elements` (adopt the manual
      bundle install), `1password`, `bitwarden`, `google-chrome`, `firefox`.
      `homebrew.onActivation.cleanup = "none"` until Phase 5. No `masApps` (unused).
- [ ] Chrome policy baseline (`com.google.Chrome` managed prefs via
      `system.defaults.CustomUserPreferences`): force-install 1Password extension
      (TODO: verify extension ID), minimal hardening keys; leave G Suite/sync alone.
      Defer further policy decisions until felt need.
- [ ] Firefox: full `programs.firefox` config — profile, `user.js` settings,
      search engines, NUR extensions (1Password to start) — with the app from the
      cask (module's package option = null pattern).
- [ ] Password managers: nixpkgs CLIs (`_1password-cli`, `rbw` and/or
      `bitwarden-cli`). 1Password SSH agent in `programs.ssh`
      (`IdentityAgent` → 1Password socket); git signing via SSH key.
      Bitwarden = second domain; SSH `Match` blocks if/when it holds keys.
- [ ] Harness bootstrap: activation/run-once script installing Claude Code native
      installer; HM-link individual config files (`~/.claude/settings.json`, etc.).

**Gate:** `chrome://policy` shows baseline; deleting the Firefox profile and
rebuilding restores it from repo; `ssh` prompts via 1Password; cask self-updates
confirmed working (no permission errors).

## Phase 4 — Shell + CLI environment ☐

- [ ] **bash**: `programs.bash` in HM; `environment.shells = [ pkgs.bashInteractive ]`;
      manual once: `chsh -s /run/current-system/sw/bin/bash`.
      (Failure-mode note: if `/run` ever breaks, `/bin/bash` remains the rescue shell.)
- [ ] `programs.git` (incl. `includeIf "gitdir:"` fragment setting
      `core.hooksPath = .githooks` for this repo — makes the gitleaks hook
      activation declarative per machine), `programs.ssh`, `programs.tmux`,
      `programs.vim` (plugins from `pkgs.vimPlugins`; existing vimrc sourced as
      plain file initially), `programs.alacritty` (config), `programs.direnv` +
      nix-direnv (also puts the devShell's gitleaks on PATH for the hook).
- [ ] Alacritty **app** from nixpkgs (pinned; version+config together);
      mac-app-util makes it Spotlight-visible.
- [ ] Staples from nixpkgs: `nodejs`, `deno`, `bun`, `go`, `kubectl`
      (+ per-project versions via dev shells/direnv when needed).
- [ ] Existing dotfiles migrated per preference order (HM module first; plain-file
      escape hatch where translation isn't worth it). Iterate-heavy configs may use
      `mkOutOfStoreSymlink` for edit-without-rebuild.

**Gate:** fresh terminal = fully configured bash/vim/tmux; Alacritty from Spotlight;
`bash --version` ≥ 5.

## Phase 5 — Converge and enforce ☐

- [ ] Reconcile Phase 0 inventory: every app/package either declared or consciously
      dropped. Then flip `homebrew.onActivation.cleanup = "zap"`.
- [ ] `BOOTSTRAP.md`: the irreducible per-machine manual checklist —
      WG-installer run · TCC grants (Karabiner) · input source + logout ·
      `chsh` · 1Password sign-in · browser sign-ins · harness login ·
      `git config core.hooksPath .githooks` until Phase 4 makes it declarative.
- [ ] gitleaks hook verified; README documents the appliance tier + secrets rules.

**Gate:** zap-mode rebuild changes nothing; checklist tested mentally against a
hypothetical fresh machine.

## Phase 6 — Second host (`old`) ☐

- [ ] Port the old laptop's existing nix-darwin + HM config into this repo as
      `hosts/old.nix` (+ shared modules); `darwin-rebuild switch --flake .#old`.
      Until then it consumes this repo's `homeManagerModules.*` as a flake input.
- [ ] Add `security.pam.services.sudo_local.touchIdAuth = true` if it has Touch ID.
- [ ] Converge; **diff the two machines' experience** — every gap found is a repo
      fix, not a local fix.

**Gate:** old laptop reaches declared state using only the repo + BOOTSTRAP.md.

---

## Deferred backlog (designed, not scheduled)

- `nix.linux-builder` (sized: ~4 cores / 6 GB on small machines; launchd
  `ProcessType = "Interactive"`; aarch64-linux only — no x86 via QEMU).
- colima (`--vm-type vz`) + docker CLI + k3d/kind for containers/k8s.
- NixOS VMs: nixos-lima (headless), vfkit/phaer setup (GUI 2D), UTM+virgl (GUI 3D);
  NixOS test framework for multi-node network labs.
- sops-nix (age keys held in 1Password) when first server/VM needs deploy secrets;
  colmena `keyCommand` with `op`/`rbw` for push-time injection.
- Lix experiment: `nix.package = pkgs.lixPackageSets.stable.lix` (+ overlay).
- Standalone-HM flip on `work` if password-prompt friction proves real.
- klfc (JSON → keylayout/XKB/KLC) if the layout ever gets refined cross-platform.
- Browser extension/policy parity beyond 1Password.
- vaultwarden as declarative NixOS service (self-hosted Bitwarden sync).
- `nixosConfigurations` for Linux metal/VMs reusing `modules/home/`.

## Open TODOs

- [ ] Pick exact Programmer Dvorak keylayout variant + source.
- [ ] Karabiner config delivery mechanism (symlink finickiness — test on `work`
      before committing; see Phase 2).
- [ ] Verify: login-window input menu defaults key; Karabiner system-default config
      path; 1Password Chrome extension ID; bash-from-nix login shell on MDM device.
- [x] Decide repo name → **`nix-macos-config`** (github.com/milesAwayAlex).
- [ ] Firefox user.js starting set (privacy baseline vs. vanilla).

## Risk register (from the pre-mortem)

- Maintenance-to-benefit inversion → keep config boring, weekly bot PRs, graceful-abandonment design.
- macOS major releases break nix-darwin modules → never day-one upgrade macOS.
- Declared-vs-actual drift (System Settings clicks) → periodic re-read; partial coverage is honest.
- MDM conflict (work machine) → Phase 0 gate.
- Eval is single-threaded upstream → irrelevant at this repo's scale; Determinate
  Nix is the escape hatch if a monorepo-scale flake ever hurts.
