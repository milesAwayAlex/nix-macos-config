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
| Spotlight/Dock fix | Built-in successors to mac-app-util, verified 2026-08-18 against 26.05 sources: HM `targets.darwin.copyApps` (default on `home.stateVersion` ≥ 25.11) copies `home.packages` apps to `~/Applications/Home Manager Apps`; nix-darwin copies `environment.systemPackages` apps to `/Applications/Nix Apps` | Real copies → Spotlight indexing, stable Dock pins, sane TCC. Caveat: updating an existing copied bundle may raise a one-time App Management permission prompt for the terminal running the switch. |
| Secrets | 1Password-first runtime references (`op`, SSH agent); **nothing in repo/store**; sops-nix deferred until first server/VM | gitleaks pre-commit as seatbelt. Bitwarden = second domain; vaultwarden self-host option later. |
| Browsers | **Both first-class.** Chrome: cask + declared policy baseline (G Suite daily driver). Firefox: cask app + full `programs.firefox` config (profile, user.js, NUR extensions). | Both self-update (appliance tier). Never install browsers from nixpkgs on macOS. |
| AI harnesses | Native self-updating installers, run once by hand from `BOOTSTRAP.md`; config **deliberately unmanaged** (D13) | Binary = appliance. nixpkgs' `claude-code` is unfree, uncached and lags the running version; the harness rewrites its own settings, so declaring them would fight the tool. |
| GC | `nix.gc.automatic`, `--delete-older-than 14d`, `nix.optimise.automatic` | Never bare `-d`. Module-mode HM = single profile chain. |
| Shell | **bash** (modern bash 5 from nixpkgs as login shell; macOS ships 3.2) | `programs.bash` in HM; `/etc/shells` via `environment.shells`; one manual `chsh`. |
| Editor | **vim** (`programs.vim`, plugins from `pkgs.vimPlugins`; LSP via yegappan/lsp, a flake input per D11) | Ported clean 2026-08-19 — the sourced-vimrc escape hatch proved unnecessary after the line-by-line review. |
| Sudo ergonomics | Work machine: no Touch ID, no NOPASSWD (≈ passwordless root; unacceptable on managed hardware). Personal/old machine: `security.pam.services.sudo_local.touchIdAuth = true`. | Rebuilds are deliberate, infrequent events; browser security does NOT depend on rebuild cadence. |

## Machines

| Alias | Hardware | Status |
|---|---|---|
| `work` | This laptop, macOS 15.7.7 (Sequoia), **MDM-managed**, no Touch ID, Homebrew present | First target. Phase 0 MDM gate passed; Nix seeded 2026-08-15. |
| `old` | Old laptop (personal), running its own flake-based nix-darwin + HM config | Host #2. **Live consumer since 2026-08-16**: imports `homeModules.karabiner` via `home-manager.sharedModules` (attrpath renamed per D8 — its flake adopts the new name at its next input bump). Full port into this repo = Phase 6. |

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
      *(Now the main Phase 0 leftover — do before Phase 3's nix-homebrew
      autoMigrate; it's the raw material for Phase 5 reconciliation. The brew
      formula set already shrank by nine on 2026-08-18.)*
- [ ] Time Machine snapshot. *(Skipped ahead of the Nix seed — installer is
      receipt-reversible; still wanted before Phase 2 root activation.)*
- [x] Create **public** GitHub repo: **`nix-macos-config`** (this repo) — plan +
      README recording decisions, gitleaks pre-commit hook from commit one, MIT
      license. *(2026-08-15)*

**Gate:** MDM verdict positive; inventory committed.

## Phase 1 — Seed + skeleton — **complete 2026-08-18** ☑

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
      Portable home modules exported as `homeModules.*` (naming per D8).
- [x] Core nix settings — as planned, plus a reactive disk floor:
      `nix.settings.min-free` 10 GiB / `max-free` 20 GiB (`mkDefault`,
      host-tunable). Host identity (`system.primaryUser`, user home,
      `system.stateVersion = 7`) lives in `hosts/work.nix`.
- [x] Home-manager wired as nix-darwin module; first payload = karabiner
      (pulled forward from Phase 2, see there).
- [x] `justfile` (`switch`, `build`, `check`, `update`, `gc`, and since
      2026-08-18 `fmt` → `nix fmt` with `formatter` = nixfmt-tree; host via
      `NIXHOST`, default `work`) + gitleaks CI backstop *(2026-08-16)*. `just` + `gitleaks`
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

## Phase 2 — Input layer: Programmer Dvorak + Karabiner — **functionally complete 2026-08-18** ☑

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
      Module: `modules/home/karabiner`, exported as `homeModules.karabiner`.
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
      `homeModules.karabiner` via `home-manager.sharedModules`.
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
converge-after-edit ☑ *(proven repeatedly during the config review — every
karabiner.json iteration switched cleanly)*; reboot survival ☐ — verify at the
next natural reboot, no dedicated test needed.

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
- [ ] Password managers: 1Password SSH agent in `programs.ssh`
      (`IdentityAgent` → 1Password socket); git signing via SSH key.
      Bitwarden = second domain; SSH `Match` blocks if/when it holds keys.
      *(`op` source deferred 2026-08-20: it is nixpkgs' first unfree package,
      needing an `allowUnfreePredicate` allowlist, and the app it integrates
      with — `/Applications/1Password.app`, installed manually, adopted as a
      cask here — is the thing that would gate a later biometric-unlock
      option. Decide CLI source alongside the app, not before.)*
- [ ] Harness bootstrap — **decided 2026-08-20: manual, not activation.** The
      native installer is a one-time step on a machine that needs an
      interactive login anyway, so it lives in `BOOTSTRAP.md` rather than
      putting a curl-pipe on the `switch` path. `~/.claude/settings.json`
      stays unmanaged per D13.

**Gate:** `chrome://policy` shows baseline; deleting the Firefox profile and
rebuilding restores it from repo; `ssh` prompts via 1Password; cask self-updates
confirmed working (no permission errors).

## Phase 4 — Shell + CLI environment — **complete 2026-08-20** ☑

- [x] **bash + ssh** *(config slice done 2026-08-18)*: `~/configs/bashconf`
      reviewed line-by-line → `programs.bash` + `programs.readline` in
      `modules/home/bash/` (prompt sanitized into `prompt.bash`; `history -a`
      added for cross-tmux-pane history; HISTSIZE 100k). 🔴 Review found a
      live Spacelift API key + a commented `ghp_` PAT exported in the tracked
      `.bashrc` of the **public** configs repo — never committed (verified
      `log -S` empty), rotation on Alex; Spacelift stays machine-local until
      the 1Password step. Machine-local hook = `~/.bashrc.local` (**D10**):
      Aikido cert blocks, nvm, gcloud (Phase 3), deno, Postgres PATH
      (postgres itself deferred; the line only provides psql). Dropped:
      Intel brew + `ibrew`, jenv, tabtab, Rancher PATH, cargo, vendored 2023
      completions (nix bash-completion framework instead — test lazy-load,
      may need darwin `environment.pathsToLink`). PATH: own bins prepended,
      brew appended — nix wins by construction. `programs.ssh` in
      `modules/home/ssh.nix` (`settings` shape; ControlPath moved from a
      predictable /tmp name to hashed `~/.ssh/cm-%C`). Login-shell flip:
      `environment.shells = [ pkgs.bashInteractive ]` in darwin core;
      manual once: `chsh -s /run/current-system/sw/bin/bash` (if `/run` ever
      breaks, `/bin/bash` remains the rescue shell). Pre-switch: populate
      `~/.bashrc.local`, then remove `~/.bashrc` `~/.bash_profile`
      `~/.profile` `~/.inputrc` `~/.ssh/config`. Post-slice fixes
      2026-08-18: guarded `. /etc/bashrc` in bashrcExtra (non-login shells
      otherwise get no nix env) and tmux `set-environment -gr` on the
      set-environment guard (path_helper demotes nix dirs in login panes
      while the inherited guard blocks the rebuild — /usr/bin/git had been
      shadowing nix git inside tmux since the brew uninstall). Then
      **standardized all interactive shells on login**: alacritty passes
      `--login` (was a ported accident of the old config); tmux panes were
      already login-by-default; both fixes remain as armor for stray
      non-login shells.
- [x] **vim** *(core slice done 2026-08-19)*: the CoC-era `~/.vimrc`
      (amix-derived) reviewed line-by-line and ported clean to
      `programs.vim` in `modules/home/vim/` — settings in vim9script
      `config.vim`, store paths handed over via `g:deps` (exported as
      `homeModules.vim`; consumers pass the `vim9-lsp` flake input via
      home-manager's `extraSpecialArgs`, D11). CoC, its 16 runtime-npm
      extensions (679 MB in `~/.config/coc`), and the node host dropped;
      LSP is yegappan/lsp (vim9script, in-process), with `nil` piloting on
      nix files (`,f` formats through nixfmt via nil's external-formatter
      hook). Kept: fugitive, gitgutter, surround, nerdtree;
      onedark swapped for **dracula** 2026-08-20 to match glow's style
      (`g:dracula_colorterm = 0` keeps the terminal background showing); added fzf.vim (`^P` files, `,b` buffers, `,/`
      ripgrep). Dropped: nerdcommenter (vim 9.1 ships a native `comment`
      package if missed), polyglot (dormant since 2022; the 9.1 runtime is
      fresher), prisma/snippets/emmet fossils, `lazyredraw`, the dead
      `Ack`/`Bclose` helpers, the hand-rolled statusline (vim-sensible's
      `laststatus=2` overridden back to 0). **Recovery world:**
      the HM vim runs `-u <store vimrc>` and removes `~/.vim` from
      packpath/runtimepath, so the old setup (`~/.vimrc` symlink +
      `~/.vim/pack` clones) stays intact under `/usr/bin/vim` (plain `vi`
      resolves to nix vim) until the post-confidence purge; the packpath
      exclusion is permanent armor against manual installs leaking in.
      **LSP roster done 2026-08-19** (11 servers, all verified attaching):
      nil+nixfmt (nix), terraform-ls (`tf`/`terraform` — vim picks either
      depending on file content), **deno** (TS/JS/TSX — brings its own
      TypeScript plus deno fmt/lint, so the node story stays deferred;
      requires `initializationOptions.enable`, silent without it),
      yaml-language-server, helm-ls (+`vim-helm` for ft=helm; drives yamlls
      itself), bash-language-server (shellcheck bundled in the nixpkgs
      wrapper, shfmt pointed at explicitly), taplo (toml), vscode-json /
      css / html (`provideFormatter` on), dockerfile-language-server,
      markdown-oxide (Obsidian-shaped: wikilinks, backlink code lens,
      daily notes, create-missing-note code action) and harper-ls
      (offline grammar, also on text/gitcommit). SQL
      has no server until the postgres slice — `gq` pipes through sqlfluff
      (postgres dialect, a guess to revisit). Node-based servers ship their
      own pinned `nodejs-slim`, so none of this touches nvm or project
      toolchains. Completion: yegappan/lsp's autoComplete pops the menu as you
      type; omniComplete is enabled too so `<C-x><C-o>` is a manual
      trigger. Deferred: gopls and rust-analyzer with their toolchains,
      eslint (needs the node story), tailwind/prisma/emmet dropped.
      Remaining vim slices: per-buffer LSP maps
      (`K` currently global) and completion tuning; a deliberate bindings/plugin-usage
      review and controls overhaul (after everything else settles);
      upstream yegappan/lsp to nixpkgs once
      the dust settles (weeks out); a notes/PKM step if the Obsidian-like
      idea firms up (markdown-oxide is already the editor half; zk is the
      CLI-notebook alternative, Obsidian itself is packaged); the purge (rm the `~/.vimrc` symlink,
      archive `~/.vim`, reclaim `~/.config/coc`, retire
      `~/configs/vimconf`).
- direnv + nix-direnv **parked 2026-08-18** (was never installed — a proposed
      addition, not a port; gitleaks/just are global via `home.packages`, so
      the hook needs nothing). Revisit when a real per-project-toolchain need
      appears at work (auto-loading devShells per repo).
- [x] **git** *(config slice done 2026-08-18)*: `~/.gitconfig` reviewed
      line-by-line against the 2.54 man pages, ported to `programs.git` in
      `modules/home/git.nix` (exported as `homeModules.git`). Kept: identity
      (public since commit 1 anyway), untrackedCache / parallel checkout /
      writeCommitGraph / pack.threads; added: `init.defaultBranch main`,
      `pull.ff only`, zdiff3, histogram. Dropped: 2.54-default fossils,
      `gc.auto=10` (near-constant gc), brew-gh credential helpers (SSH-only
      now). Hook activation now declarative via a `hasconfig:remote.*.url`
      include (retires D7's manual step). `~/.gitconfig` surrendered to
      IT/machine-local entries per **D9** — post-switch, trim it to the
      Aikido `http.sslCAInfo` line; pre-switch, delete `~/.config/git/ignore`
      (its one Claude-Code-written line moved into `programs.git.ignores`).
      Deferred: commit signing (own step later — when it lands, also add a
      signature-required rule to the GitHub ruleset); `git maintenance` skipped
      (HM support is systemd-only; default gc cadence suffices); rerere
      skipped (repeated-rebase workflows absent).
- [x] **GitHub repo hardening** *(2026-08-18, during the git slice)*: default
      branch renamed `master` → `main` (GitHub redirects old URLs; repo text
      was already branch-agnostic; on `old`, verify the flake input carries
      no `?ref=master` before its next update); ruleset
      `protect-default-branch` blocks force-push and deletion, targeting the
      default branch symbolically; wiki + projects disabled. Confirmed
      already-good: secret scanning + push protection enabled (GitHub = third
      seatbelt after hook + CI), Actions `GITHUB_TOKEN` read-only, sole
      collaborator, no deploy keys or webhooks. Rest of the menu → the
      PR-guards pass (backlog).
- [x] **tmux** *(config slice done 2026-08-18)*: `~/configs/tmux/.tmux.conf`
      reviewed against the 3.6a man page, ported to `programs.tmux` in
      `modules/home/tmux.nix` (exported as `homeModules.tmux`). Deltas:
      `default-terminal` xterm-256color → tmux-256color (man requires a
      screen/tmux derivative; macOS ships the entry); truecolor via
      `terminal-features ",alacritty:RGB"` (alacritty's terminfo lacks RGB —
      the old `xterm*` pattern never matched the new outer); focus-events on;
      brew bash → `bashInteractive`; redundant defaults dropped. Copy-mode
      `y` should now reach the macOS clipboard via OSC 52 (alacritty `Ms` +
      `set-clipboard external`) — verify. After switch: delete the
      `~/.tmux.conf` symlink (found before HM's XDG file) and
      `tmux kill-server` once. Bindings-quirks review = open offer.
      Tuning 2026-08-18: prefix → `C-Space` (C-b freed for apps; space-as-
      shift means the chord lands on space release — rolling breaks it),
      resize flashes the pane size, five-cell resize tier dropped, `prefix g`
      renders clipboard markdown in an 80-column glow split, prefix-armed
      asterisk beside the session tab in status-left, `prefix y` copies the
      whole scrollback to the macOS clipboard.
- [x] Alacritty **app** from nixpkgs *(pulled forward 2026-08-18: 0.17.0 via
      `home.packages` + default copyApps; the manual 0.12.2 in /Applications
      stays side-by-side until confidence, then gets deleted)*. **Config slice
      done 2026-08-18**: the pre-TOML `~/.alacritty.yml` reviewed line-by-line
      against the 0.17 man pages and ported to `programs.alacritty` in
      `modules/home/alacritty.nix` (exported as `homeModules.alacritty`);
      Hack provisioned via `hack-font` (HM copies fonts to
      `~/Library/Fonts/HomeManager`). After confidence, deletable: the old
      app, `~/.alacritty.yml` + `~/configs/alacritty/`, and the four manual
      Hack TTFs in `~/Library/Fonts`.
- [x] Staples from nixpkgs *(2026-08-20)*: **node** `nodejs_22` (LTS, pinned
      to the major) + `cspell`, in `modules/home/node.nix` — nvm retired per
      D12, since every `.nvmrc` under `~/code` says v22 and the real per-repo
      variance is pnpm, which corepack resolves from `packageManager`. Global
      prefix redirected via `NPM_CONFIG_PREFIX` (never `~/.npmrc` — npm writes
      auth tokens there). **k8s bundle** in `modules/home/k8s.nix`: `kubectl`,
      `kubectx`, `kubernetes-helm`, `k9s`, `argocd`, `argo-rollouts`, `kind`,
      and `kube-fzf` — kubectl 1.36 vs GKE 1.35 is inside the ±1 skew,
      replacing gcloud's dispatcher which resolved to 1.27 and warned on every
      call. `skaffold` dropped as unused. `kube-fzf` is not in nixpkgs, so it
      is packaged in `packages/kube-fzf.nix` per D14, shaped for a nixpkgs PR
      once it has run for a while. **gcloud** in
      `modules/home/gcloud.nix` with `withExtraComponents
      [gke-gcloud-auth-plugin]`. `gh` grew a config module
      (`git_protocol = ssh`). `bun` and `go` deliberately skipped — no
      toolchain need yet. Per-project versions via dev shells/direnv when
      needed.
      *(Pulled forward 2026-08-18: `fzf`, `git`, `glow`, `ripgrep`, `tmux`,
      `jq`, `yq-go`, `htop`, `gh` as packages-only in `modules/home/pkgs.nix` —
      locked-nixpkgs versions beat the stale brew set on all nine; the brew
      formulae were uninstalled, so the nix copies are live. Configs still land
      here in Phase 4. GNU coreutils deliberately deferred to the shell work —
      unprefixed BSD→GNU userland flip is a decision, not a package add.)*
- [x] **GNU userland** *(2026-08-20)*: `coreutils`, `findutils`, `gnused`,
      `gnugrep`, `gawk`, `gnutar`, `diffutils`, `gnumake` unprefixed in
      `modules/home/gnu.nix` — the BSD→GNU flip this phase had deferred as a
      decision rather than a package add, taken per **D15** for CI parity.
      `ls -G` alias corrected to `--color=auto` in the same change.
- [x] Existing dotfiles migrated per preference order (HM module first;
      plain-file escape hatch where translation isn't worth it) — **complete
      2026-08-20**. Every live config is declared: bash/readline, ssh, git,
      tmux, alacritty, vim, karabiner, glow, gh. `mkOutOfStoreSymlink` was
      never needed. What remains in `~/configs` is dead files awaiting
      deletion, not unmigrated config — that is Phase 5 reconciliation, along
      with the CoC/nvm/brew-gcloud reclaim. The `~/.config/karabiner ->
      ~/configs/karabiner` symlink (which had activation writing into a public
      git tree) was replaced with a real directory 2026-08-20; only
      `~/.vimrc` → `vimconf/.vimrc` stays live, deliberately, for the
      `/usr/bin/vim` recovery path.

**Gate:** fresh terminal = fully configured bash/vim/tmux ☑; Alacritty from
Spotlight ☑; `bash --version` ≥ 5 ☑. **Phase 4 complete 2026-08-20.**

## Phase 5 — Converge and enforce ☐

- [ ] Reconcile Phase 0 inventory: every app/package either declared or consciously
      dropped. Then flip `homebrew.onActivation.cleanup = "zap"`. Carried in
      from Phase 4 as one deletion pass: `~/configs` (all but `vimconf`, which
      backs the recovery vim), `~/.vim` + `~/.config/coc` (679 MB), `~/.nvm`
      (2.1 GB), brew's google-cloud-sdk (2.3 GB), the manual Alacritty 0.12.2
      and hand-installed Hack TTFs, and the dangling `~/git_completion` and
      `~/.alacritty.yml` symlinks. 🔴 Also the Spacelift key + `ghp_` PAT in
      `~/configs/bashconf/.bashrc` — rotate before that repo is touched again.
- [ ] `BOOTSTRAP.md` *(seeded 2026-08-20 with the harness entry)*: the
      irreducible per-machine manual checklist —
      WG-installer run · TCC grants (Karabiner) · input source + logout ·
      `chsh` · 1Password sign-in · browser sign-ins · harness login ·
      `git config core.hooksPath .githooks` until Phase 4 makes it declarative.
- [ ] README documents the appliance tier. *(Already done: gitleaks hook
      verified 2026-08-15 via refusal test; secrets rules documented in
      README + CLAUDE.md.)*

**Gate:** zap-mode rebuild changes nothing; checklist tested mentally against a
hypothetical fresh machine.

## Phase 6 — Second host (`old`) ☐

- [ ] Port the old laptop's existing nix-darwin + HM config into this repo as
      `hosts/old.nix` (+ shared modules); `darwin-rebuild switch --flake .#old`.
      Until then it consumes this repo's `homeModules.*` as a flake input.
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
  full build on free arm64 macos runners). GitHub-side hardening scoped
  2026-08-18: pin third-party actions by commit SHA (+ flip the repo's
  `sha_pinning_required` toggle), Dependabot version updates for the
  `github-actions` ecosystem (it can't track flake.lock), required status
  checks once the eval check exists, `deleteBranchOnMerge`.
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
