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

Operating conventions (tool sourcing, file delivery, layout, GC, vendoring,
updates, hooks) are recorded ADR-style in [DECISIONS.md](DECISIONS.md) —
principles here say *why*, that file says *how*.

## Stack decisions (settled)

| Layer | Choice | Key rationale |
|---|---|---|
| Installer (seed) | [NixOS/nix-installer](https://github.com/NixOS/nix-installer) (the community fork, graduated from `experimental-nix-installer`; pinned 2.35.1) | Determinate-installer ergonomics (receipt uninstall, macOS-upgrade survival), installs upstream Nix, distributed from `artifacts.nixos.org`. Since 2026-01 the DetSys installer installs Determinate Nix *only*, so this fork is the sole receipt-style path to upstream Nix. Seed only — see below. |
| Interpreter | Upstream CppNix, via `nix.enable = true` + `nix.package` | nix-darwin manages Nix itself; upgrades ride the rebuild train. Lix = one-line `nix.package` flip later. Determinate Nix rejected for now: proprietary nixd + `nix.*` carve-outs vs. our single-surface principle. |
| System config | nix-darwin (flake-based) | `system.defaults`, launchd, activation scripts, homebrew driver. |
| User config | home-manager **as nix-darwin module** | One command, one lock, one GC, atomic generations. Flip to standalone per-machine only if no-Touch-ID password friction grates (work machine candidate). |
| nixpkgs | **26.05 release train**: `nixpkgs-26.05-darwin` + matched `nix-darwin-26.05` + HM `release-26.05`; weekly lock bumps via `update-flake-lock` action | Flipped from unstable 2026-08-15, pre-payload ("zero to unstable felt iffy"). Darwin-tested stable channel; train bump = twice-yearly deliberate chore (26.11 due ~Nov 2026; 26.05 EOL ~Dec 2026). Escape hatches: flip to unstable (3 input lines) if a forced macOS update needs master-only fixes; surgical secondary unstable input if package freshness hurts (Phase 4). |
| GUI apps | Homebrew casks via nix-darwin + **nix-homebrew** (taps pinned as flake inputs, `autoMigrate` adopts existing install) | Casks for self-updating/permission-heavy apps; nixpkgs + mac-app-util for stable dev GUI (Alacritty). |
| Spotlight/Dock fix | ~~mac-app-util module~~ — dropped 2026-08, functionality upstreamed | Was: trampolines fixing Spotlight/Dock/TCC for nix-installed .apps. Verify the built-in equivalent when Phase 4 puts Alacritty in from nixpkgs. |
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
| `old` | Old laptop (personal), running its own flake-based nix-darwin + HM config | Host #2. **Live consumer since 2026-08-16**: imports `homeManagerModules.karabiner` via `home-manager.sharedModules`. Full port into this repo = Phase 6. |

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
- [x] Flake skeleton *(2026-08-15)*: inputs pinned to the 26.05 release train
      (see nixpkgs row); mac-app-util dropped (upstreamed — verify the built-in
      equivalent when Phase 4 installs nixpkgs GUI apps); nix-homebrew joins in
      Phase 3. Layout: `modules/darwin/core.nix` (portable policy),
      `modules/home/` (portable user config), `hosts/work.nix` (host identity).
      Portable home modules exported as `homeManagerModules.*`.
- [x] Core nix settings — as planned, plus a reactive disk floor:
      `nix.settings.min-free` 10 GiB / `max-free` 20 GiB (`mkDefault`,
      host-tunable). Host identity (`system.primaryUser`, user home,
      `system.stateVersion = 7`) lives in `hosts/work.nix`.
- [x] Home-manager wired as nix-darwin module; first payload = karabiner
      (pulled forward from Phase 2, see there).
- [x] `justfile` (`switch`, `build`, `check`, `update`, `gc`; host via `NIXHOST`,
      default `work`) + gitleaks CI backstop *(2026-08-16)*. `just` + `gitleaks`
      added to `home.packages`. Deliberately deferred to a future **PR-guards
      pass**: the `update-flake-lock` weekly bot (solo workflow = `just update`
      + local rebuild review, so the bot saves nothing yet) and the CI eval
      check (free on a public repo, but low value pre-PR-guards).
      `CLAUDE.md` written 2026-08-18.
- [x] First `sudo darwin-rebuild switch --flake .#work` *(2026-08-15)* — no
      /etc move-aside needed: nix-darwin's known-hash list silently adopted the
      installer's stock bashrc/zshrc/nix.conf.

**Gate:** second switch is a no-op ☑; `nix.package` owns the running Nix ☑
(nix 2.34.8 from 26.05 — below the 2.35.1 seed, expected on stable);
bot PR pipeline — re-scoped 2026-08-16 (deferred to the PR-guards pass).
**Phase 1 complete** (CLAUDE.md landed 2026-08-18).

## Phase 2 — Input layer: Programmer Dvorak + Karabiner ☐

Goal: both active **at the login window** (FileVault pre-boot stays QWERTY — EFI,
unavoidable; type that password in QWERTY).

- [x] Vendor the layout *(2026-08-17)*: `modules/darwin/input/programmer-dvorak.bundle`
      — Kaufmann's official macOS distribution (`ProgrammerDvorak-1_2_13.pkg.zip`,
      sha256 verified against the Homebrew cask pin, payload byte-identical to
      the bundle already installed on `work`). Resolves the pick-a-variant TODO.
      (A `programmer-dvorak` cask exists as the alternative; vendoring chosen —
      reviewable XML, no homebrew dependency, static artifact.)
- [x] System-wide install via root activation (`modules/darwin/input`):
      diff-guarded `cp -R` to `/Library/Keyboard Layouts/Programmer Dvorak.bundle`.
- [x] Login-window input menu:
      `system.defaults.CustomSystemPreferences."com.apple.loginwindow".showInputMenu`
      (nix-darwin has no typed option for it — checked against 26.05 source).
- [ ] Karabiner-Elements app: currently a manually-installed bundle (brew cask was
      broken at install time) — adopt as cask in Phase 3 (`--force`/adopt moment;
      recheck whether the cask works).
- [x] Config delivery — **decided 2026-08-15: copy-on-activation.** Symlink
      refuted by live test on `work`: the watcher misses edits made through
      the link AND GUI edits replace the link. HM `home.activation` (after
      `writeBoundary`) converges a real writable file, `cmp`-guarded so no-op
      switches stay no-op; drift is overwritten on switch (noted in output).
      Module: `modules/home/karabiner`, exported as `homeManagerModules.karabiner`.
      Per-machine device blocks: ship the union of both machines' devices
      (entries for absent devices are inert). Nix-attrset `builtins.toJSON`
      generation stays the later option if real per-machine divergence appears.
- [x] Config reviewed line-by-line *(2026-08-16)*: fossil TouchBar-era device
      entry removed (old Intel Mac's internal keyboard ID); scramble kept as
      profile-root simple modifications (device-scoped `{is_keyboard: true}`
      failed on current Karabiner); readline rule re-bucketed — byte-identity
      chords (^I ^[ ^M ^H) unconditional, arrows excluded only in Alacritty,
      ^W restored, ^U reimplemented as native cmd+⌫; deliberate ctrl+cmd layer
      (cmd optional on i/m/h/b/p/n; excluded on f = fullscreen). Cheatsheet:
      `KEYBOARD.md`. **Cross-machine reuse live**: `old` imports
      `homeManagerModules.karabiner` via `home-manager.sharedModules`.
- [x] Pre-login remapping *(2026-08-17)*: activation copies the repo
      karabiner.json to `/Library/Application Support/org.pqrs/config/karabiner.json`
      — path confirmed empirically (the GUI "use before login" button created it,
      contents already identical to the repo). Activation owns the file now; the
      GUI button is obsolete. Module exported as `darwinModules.input` for `old`.
- [x] Manual (on `work`: all pre-existing — extension + Input Monitoring
      approved in Phase 0, input source enabled). For fresh machines this
      checklist moves to `BOOTSTRAP.md` (Phase 5).

**Gate:** layout selectable and Karabiner remapping live at the login window ☑
*(logout test passed 2026-08-18; FileVault pre-boot stays QWERTY as expected)*;
survive reboot + converge-after-edit — pending incidental verification.

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
      *(Pulled forward 2026-08-18: `fzf`, `git`, `glow`, `ripgrep`, `tmux` as
      packages-only in `modules/home/pkgs.nix` — locked-nixpkgs versions beat
      the stale brew set on all five; configs still land here in Phase 4;
      brew formulae shadow the nix copies until uninstalled.)*
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

- **PR-guards pass**: `update-flake-lock` weekly bot (posture note: pair with
  `cachix/install-nix-action` for upstream Nix, PR via
  `peter-evans/create-pull-request`; GITHUB_TOKEN-created PRs don't trigger
  workflows — needs a fine-grained PAT for CI-on-bot-PRs) + CI eval check
  (`nix eval .#darwinConfigurations.<host>.system.drvPath` on ubuntu; optional
  full build on free arm64 macos runners).
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

- [x] Pick exact Programmer Dvorak keylayout variant + source → official
      Kaufmann 1.2.13 bundle, checksum-verified, vendored 2026-08-17.
- [x] Karabiner config delivery mechanism → copy-on-activation (symlink refuted
      by live test on `work`, 2026-08-15; see Phase 2).
- [ ] Verify: 1Password Chrome extension ID; bash-from-nix login shell on MDM
      device. *(Resolved 2026-08-17: login-window input-menu key =
      `showInputMenu` via `CustomSystemPreferences`; Karabiner system config
      path = `/Library/Application Support/org.pqrs/config/karabiner.json`.)*
- [x] Decide repo name → **`nix-macos-config`** (github.com/milesAwayAlex).
- [ ] Firefox user.js starting set (privacy baseline vs. vanilla).

## Risk register (from the pre-mortem)

- Maintenance-to-benefit inversion → keep config boring, weekly bot PRs, graceful-abandonment design.
- macOS major releases break nix-darwin modules → never day-one upgrade macOS.
- Declared-vs-actual drift (System Settings clicks) → periodic re-read; partial coverage is honest.
- MDM conflict (work machine) → Phase 0 gate.
- Eval is single-threaded upstream → irrelevant at this repo's scale; Determinate
  Nix is the escape hatch if a monorepo-scale flake ever hurts.
