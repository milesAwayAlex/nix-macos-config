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
| Sudo ergonomics | `security.pam.services.sudo_local.touchIdAuth = true` on any machine with the sensor — both have one. Never NOPASSWD: that is passwordless root, and Touch ID is a second factor rather than the removal of one. | Rebuilds are deliberate, infrequent events, so the prompt is cheap either way. |

## Machines

| Alias | Hardware | Status |
|---|---|---|
| `work` | This laptop, MacBookPro18,2, macOS 15.7.7 (Sequoia), **MDM-managed**, Homebrew present | First target. Phase 0 MDM gate passed; Nix seeded 2026-08-15. |
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
      user is admin with sudo.
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
- [x] `chrome://management` reports the browser **not** centrally managed, so
      a Chrome policy baseline written to `/Library/Preferences` should take
      (Phase 3).
- [x] Inventory taken 2026-08-20 — brew bundle dump, applications, dotfile
      ownership, `defaults` domains — as `INVENTORY.md`, deliberately
      **uncommitted**: it is a machine manifest, and the repo is public. Same
      for `DEFAULTS-REVIEW.md`, the 197 typed `system.defaults` keys read off
      this machine and diffed against their documented defaults.
- [x] Time Machine snapshot **dropped 2026-08-20** — the installer is
      receipt-reversible and the migration is far enough along that rolling
      back is the larger risk.
- [x] Create **public** GitHub repo: **`nix-macos-config`** (this repo) — plan +
      README recording decisions, gitleaks pre-commit hook from commit one, MIT
      license. *(2026-08-15)*

**Gate:** MDM verdict positive; inventory taken.

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
- [x] Karabiner-Elements app declared as a cask *(2026-08-20)*: the cask runs
      the official pqrs `.pkg`, so it is the same installer by another name,
      and it is `auto_updates` (D16). The nix path — nixpkgs
      `karabiner-elements` plus nix-darwin's `services.karabiner-elements` —
      was rejected: it rehomes the DriverKit manager and reimplements the
      daemons against store paths, and Input Monitoring is granted per binary
      path, so every version bump would need re-approval by hand on the
      machine whose login window depends on the remap.
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

- [x] **nix-homebrew** *(2026-08-20)* owns the Homebrew installation, so a
      fresh machine needs no curl-bash. Homebrew cannot be a nix package — a
      self-modifying git checkout that writes Cellar, Caskroom and receipts
      into its own prefix cannot live in a read-only store, and nixpkgs has no
      `brew` — and brew cannot be a throwaway activation tool either, because
      its memory of what is installed *is* the prefix. nix-homebrew clones
      `Homebrew/brew` from a flake input (pinned 6.0.16, Ruby from nixpkgs
      rather than brew's portable download). `autoMigrate` adopts an existing
      prefix by deleting only the git-tracked files of the checkout; Cellar,
      Caskroom, bin and `Library/Taps` are ignored state and survive.
      `enableRosetta = false`; `mutableTaps = false`, which with no taps
      declared points `Taps` at an empty store path so `brew tap` cannot write
      (D16). The twelve taps this machine carried were untapped by hand and
      the emptied `Library/Taps` directory removed with them, since it blocks
      activation whenever it exists as a real directory.
- [x] Casks, `modules/darwin/homebrew.nix` *(2026-08-20)*: `1password`,
      `google-chrome`, `karabiner-elements`. All three carry `auto_updates`,
      which is now the admission rule (D16). Dropped from the earlier list:
      `bitwarden` (unused), `firefox` (not installed — revisit with the
      `programs.firefox` bullet), `slack` (bootstrap, D17), `ngrok` (unused —
      cheap to add back), `utm` (no Sparkle updater, so it went to nixpkgs).
      `cleanup = "none"`, `autoUpdate = false`, `upgrade = false` — the reasons
      are in D16. Per-host keep-list hook stubbed in `hosts/work.nix`.
      Karabiner's nix path — nixpkgs `karabiner-elements` 15.7.0 plus
      nix-darwin's `services.karabiner-elements` — was read and rejected: it
      rehomes the DriverKit manager and reimplements the daemons against store
      paths, and Input Monitoring is granted per binary path, so every version
      bump would need re-approval by hand on a machine whose login window
      depends on the remap.
- [x] Chrome policy, `modules/darwin/chrome.nix` *(2026-08-21)*: 1Password
      force-installed (`aeblfdkhhhdcdjpifhhbdiojplfjncoa`), Chrome's own
      password manager and address/card autofill off. Written to
      `/Library/Preferences/com.google.Chrome` — the attribute name reaches
      `defaults write` verbatim from a root activation script, so a bare
      domain would land in root's own preferences. Confirmed live in
      `chrome://policy`. Not forced the way a profile would be; nix-darwin
      cannot install profiles, so mandatory policy is out of reach. G Suite
      and sync untouched.
- [x] 1Password ssh agent *(2026-08-20)*: `Host *` `IdentityAgent` → the
      1Password socket, declared in `modules/home/work.nix` because the
      manager is the company's (D17, D19). The value carries its own quotes —
      the path has a space in it and an unquoted directive makes ssh reject
      the whole config file. Switching the agent on in the app is a bootstrap
      step; until then ssh falls back to the keys on disk. Bitwarden is the
      second domain and arrives with `old` in Phase 6.
      *(`op` itself: from nixpkgs, allowlisted in `hosts/work.nix` — D18.)*
- [x] Harness bootstrap — manual, not activation. The
      native installer is a one-time step on a machine that needs an
      interactive login anyway, so it lives in `BOOTSTRAP.md` rather than
      putting a curl-pipe on the `switch` path. `~/.claude/settings.json`
      stays unmanaged per D13.

**Gate:** `chrome://policy` shows the baseline; `ssh` prompts via 1Password;
cask self-updates confirmed working (no permission errors).

## Phase 4 — Shell + CLI environment — **complete 2026-08-20** ☑

- [x] **bash + ssh**: `programs.bash` + `programs.readline` in
      `modules/home/bash/` (prompt in `prompt.bash`, `history -a` for
      cross-tmux-pane history, HISTSIZE 100k); `programs.ssh` in
      `modules/home/ssh.nix`, ControlPath hashed to `~/.ssh/cm-%C`.
      Machine-local escape hatch is `~/.bashrc.local` (**D10**). Own bins are
      prepended and brew appended, so nix wins the PATH by construction.
      All interactive shells are login shells; `bashrcExtra` guards
      `. /etc/bashrc` and tmux sets `set-environment -gr`, as armor for stray
      non-login shells where `path_helper` demotes the nix directories.
      Login-shell flip is `environment.shells` in darwin core plus a one-time
      `chsh` (README). Open: nix's bash-completion framework lazy-loads — if
      something turns out missing it may want darwin `environment.pathsToLink`.
- [x] **vim**: `programs.vim` in `modules/home/vim/` — settings in vim9script
      `config.vim`, store paths handed over through `g:deps`, exported as
      `homeModules.vim` (consumers pass the `vim9-lsp` input via
      `extraSpecialArgs`, **D11**). LSP is yegappan/lsp: vim9script,
      in-process, no node host. Plugins: fugitive, gitgutter, surround,
      nerdtree, fzf.vim (`^P` files, `,b` buffers, `,/` ripgrep), dracula.
      **Recovery world:** the HM vim runs `-u <store vimrc>` and drops `~/.vim`
      from packpath and runtimepath, so `/usr/bin/vim` keeps a working editor
      independent of it. The packpath exclusion is permanent armor against
      manually installed plugins leaking in.
- [x] **LSP roster**: nil + nixfmt (nix), terraform-ls, yaml-language-server,
      helm-ls (+`vim-helm` for ft=helm, which drives yamlls itself),
      bash-language-server (shellcheck bundled in the nixpkgs wrapper, shfmt
      pointed at explicitly), taplo, vscode-json / css / html
      (`provideFormatter` on), dockerfile-language-server, markdown-oxide
      (wikilinks, backlink code lens, daily notes), and harper-ls — opt-in via
      `,sp` / `:Harper` rather than at startup, with `,qf` becoming
      `:LspCodeAction only:quickfix` in prose because `LspAutoFix` declines
      any diagnostic carrying more than one candidate, which is every spelling
      suggestion. TypeScript is split by project with the plugin's
      `runIfSearch` / `runUnlessSearch` on `package.json`, so exactly one
      server attaches per buffer: vtsls in node projects
      (`autoUseWorkspaceTsdk`, so diagnostics match the repo's pinned tsc),
      deno everywhere else. Formatting follows that split — a prettier in the
      repo's `node_modules` takes `,f` (its pinned version, its `.prettierrc`,
      and it echoes stdin back on ignored paths), otherwise the server does it.
      Visual `,f` stays on the server, which handles ranges. SQL has no server
      until the postgres slice; `gq` pipes through sqlfluff on the postgres
      dialect, a guess to revisit. Node-based servers ship their own
      `nodejs-slim`, independent of any project toolchain.
      Remaining: per-buffer LSP maps (`K` is global), completion tuning, a
      deliberate bindings and plugin-usage review once everything else
      settles, upstreaming yegappan/lsp to nixpkgs, and a notes/PKM step if
      the idea firms up (markdown-oxide is already the editor half; zk is the
      CLI alternative). Deferred: gopls and rust-analyzer with their
      toolchains, eslint.
- direnv + nix-direnv **parked** — gitleaks and just are global via
      `home.packages`, so nothing needs a hook. Revisit when a real
      per-project-toolchain need appears (auto-loading devShells per repo).
- [x] **git**: `programs.git` in `modules/home/git.nix` (exported as
      `homeModules.git`). `init.defaultBranch main`, `pull.ff only`, zdiff3,
      histogram, untrackedCache, parallel checkout, writeCommitGraph; identity
      in the clear, since the repo is public anyway. Hook activation is
      declarative through a `hasconfig:remote.*.url` include, which retires
      D7's manual step. `~/.gitconfig` is surrendered to IT and machine-local
      entries per **D9** — still to do: trim it to the IT cert line.
      Deferred: commit signing (when it lands, add a signature-required rule
      to the GitHub ruleset); `git maintenance` (HM support is systemd-only);
      rerere (no repeated-rebase workflow).
- [x] **GitHub repo hardening**: default branch `main`; ruleset
      `protect-default-branch` blocks force-push and deletion, targeting the
      default branch symbolically; wiki and projects disabled; secret scanning
      and push protection on (GitHub is the third seatbelt after hook and CI);
      Actions `GITHUB_TOKEN` read-only; sole collaborator, no deploy keys or
      webhooks. Rest of the menu is the PR-guards pass in the backlog. For
      Phase 6: check `old`'s flake input carries no `?ref=master`.
- [x] **tmux**: `programs.tmux` in `modules/home/tmux.nix` (exported as
      `homeModules.tmux`) — `tmux-256color`, truecolor via
      `terminal-features ",alacritty:RGB"`, focus-events on,
      `bashInteractive` as the shell. Prefix is `C-Space`, since space-as-
      shift means the chord lands on space release and rolling `C-b` breaks;
      resize flashes the pane size; `prefix g` renders clipboard markdown in
      an 80-column glow split; `prefix y` copies the whole scrollback to the
      macOS clipboard; a prefix-armed asterisk sits beside the session tab in
      status-left. Verify: copy-mode `y` reaching the macOS clipboard over
      OSC 52 (alacritty `Ms` + `set-clipboard external`). Bindings review is
      an open offer.
- [x] **Alacritty**: app from nixpkgs through `home.packages`, which HM links
      into `~/Applications/Home Manager Apps`; config in
      `modules/home/alacritty.nix` (exported as `homeModules.alacritty`).
      Hack comes from `hack-font`, which HM copies to
      `~/Library/Fonts/HomeManager`.
- [x] **Staples from nixpkgs**: **node** `nodejs_22` pinned to the major, plus
      `pnpm` — the packaged 11.x is a launcher that re-execs whatever each
      repo's `packageManager` names and stays 11.x where nothing is pinned,
      which is where the real per-repo variance lives (**D12**). Corepack was
      tried and rejected: it installs nothing itself, and `corepack enable`
      can only write shims beside the node binary (read-only store) or into a
      writable directory as store-pinned symlinks that dangle at the next GC.
      Global prefix redirected with `NPM_CONFIG_PREFIX`, never `~/.npmrc` —
      npm writes registry auth tokens into that file.
      **k8s bundle** in `modules/home/k8s.nix`: kubectl, kubectx,
      kubernetes-helm, k9s, argocd, argo-rollouts, kind, kube-fzf. kubectl
      1.36 against GKE 1.35 is inside the ±1 skew. `kube-fzf` is not in
      nixpkgs, so it lives in `packages/kube-fzf.nix` per **D14**, shaped for
      a PR once it has run a while.
      **gcloud** in `modules/home/gcloud.nix` with
      `withExtraComponents [gke-gcloud-auth-plugin]`. **gh** carries a config
      module (`git_protocol = ssh`). `bun` and `go` skipped — no toolchain
      need yet; per-project versions go through dev shells when one appears.
- [x] **GNU userland**: `coreutils`, `findutils`, `gnused`, `gnugrep`, `gawk`,
      `gnutar`, `diffutils` and `gnumake` unprefixed in `modules/home/gnu.nix`
      per **D15**, with the `ls -G` → `--color=auto` alias correction that the
      flip requires.
- [x] Every live config is declared: bash/readline, ssh, git, tmux, alacritty,
      vim, karabiner, glow, gh. `mkOutOfStoreSymlink` was never needed. One
      symlink stays live on purpose — `~/.vimrc`, backing the `/usr/bin/vim`
      recovery path until the Phase 5 purge.

**Gate:** fresh terminal = fully configured bash/vim/tmux ☑; Alacritty from
Spotlight ☑; `bash --version` ≥ 5 ☑. **Phase 4 complete 2026-08-20.**

## Phase 5 — Converge and enforce ☐

- [x] Reconcile Phase 0 inventory *(2026-08-21)*: everything brew carried is
      either declared here or consciously dropped, and
      `homebrew.onActivation.cleanup = "uninstall"` is on. The four
      third-party-tap formulae had to go by hand first — cleanup resolves
      every installed formula and aborts on a tap that no longer exists, so
      it would have failed the switch rather than skipping them. Dry run
      after that: 3 casks (`1password-cli`, `gcloud-cli`, `temurin@17`) and
      99 formulae, all superseded by nixpkgs, orphaned build dependencies, or
      dropped by decision. Redis was the one worth keeping and came back as a
      declared service rather than a brew keeper (`modules/darwin/redis.nix`);
      its brew copy goes with the rest. `"zap"` stays off for the reason in
      D16.
- [ ] Deletion pass, carried in
      from Phase 4 as one deletion pass: `~/configs` (all but `vimconf`, which
      backs the recovery vim), `~/.vim`, `~/.config/coc`, `~/.nvm`, brew's
      google-cloud-sdk, the manual Alacritty and hand-installed Hack TTFs, and
      the dangling `~/git_completion` and `~/.alacritty.yml` symlinks — about
      6 GB together. The credentials that used to sit in `~/.bashrc.local`
      and in `~/configs` are gone *(2026-08-21)*: the Spacelift key rotated
      and moved behind `op run` (D20), the `ghp_` PAT removed, and gitleaks
      reports the legacy repo clean across both its working tree and all nine
      of its commits.
- [x] Touch ID for sudo, `modules/darwin/pam.nix` *(2026-08-20)*:
      `touchIdAuth` plus `reattach`, the second because tmux's server sits in
      another bootstrap session and PAM cannot prompt it — without it nearly
      every sudo here would fall back to the password anyway. nix-darwin
      already owned `/etc/pam.d/sudo_local` and macOS already included it, so
      there was no file to adopt. `sufficient`/`optional` mean no state of the
      stack can lock sudo out. Fingerprint enrollment is manual (BOOTSTRAP).
      No MDM profile restricts biometrics on this machine.
- [ ] Finish `BOOTSTRAP.md`, the irreducible per-machine manual checklist.
      Written so far: harness install and login, adopting pre-existing casks,
      Karabiner's driver-extension and Input Monitoring approvals, fingerprint
      enrollment, 1Password sign-in with its Touch ID unlock and agent, Slack. Still to add: nix
      installer run, input source plus logout, `chsh`, browser sign-ins.
- [x] README documents the appliance tier; secrets rules are in README and
      CLAUDE.md, and the gitleaks hook is verified by refusal test.

**Gate:** zap-mode rebuild changes nothing; checklist tested mentally against a
hypothetical fresh machine.

## Phase 6 — Second host (`old`) ☐

- [ ] Port the old laptop's existing nix-darwin + HM config into this repo as
      `hosts/old.nix` (+ shared modules); `darwin-rebuild switch --flake .#old`.
      Until then it consumes this repo's `homeModules.*` as a flake input.
- [ ] Take `darwinModules.pam` here too — same sensor, same tmux problem.
- [ ] Git commit signing over ssh, which lands with Bitwarden. Not a per-host
      setting: `ssh-keygen -Y sign` reads `SSH_AUTH_SOCK` and ignores
      `IdentityAgent` (D19). Two shapes are open — Bitwarden's agent on the
      personal machine only, or a per-machine key in each manager signed
      through `op-ssh-sign` on `work`; the second keeps a personal credential
      store off employer-managed hardware. Either way, add a
      signature-required rule to the GitHub ruleset when it lands.
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
- Postgres from nixpkgs — the "postgres slice" the sqlfluff bullet in Phase 4
  defers to, which also settles that linter's dialect and whether a SQL
  language server is worth having. `Postgres.app` is a manual install with no
  brew receipt, so it is invisible to brew cleanup and survives regardless.
  Redis took this route already (`modules/darwin/redis.nix`).
- NixOS VMs: nixos-lima (headless), vfkit/phaer setup (GUI 2D), UTM+virgl (GUI 3D);
  NixOS test framework for multi-node network labs.
- sops-nix (age keys held in 1Password) when first server/VM needs deploy secrets;
  colmena `keyCommand` with `op`/`rbw` for push-time injection.
- Lix experiment: `nix.package = pkgs.lixPackageSets.stable.lix` (+ overlay).
- Standalone-HM flip on `work` if password-prompt friction proves real.
- Resolution check: assert that declared tools resolve under
  `/etc/profiles/per-user/…` or `/run/current-system/sw` rather than brew or
  `/usr/bin`. A `just` recipe over a list of names, cheap to write and cheap
  to run. Earns its place because brew's shell integration shadowed four
  declared tools and nothing in the repo noticed (D16).
- klfc (JSON → keylayout/XKB/KLC) if the layout ever gets refined cross-platform.
- Browser extension/policy parity beyond 1Password.
- Firefox as a declared browser (`programs.firefox`: profile, `user.js`,
  search engines, NUR extensions). Parked because it is not installed on
  either machine — this was scope from the template, not a felt need.
- vaultwarden as declarative NixOS service (self-hosted Bitwarden sync).
- `nixosConfigurations` for Linux metal/VMs reusing `modules/home/`.

## Open TODOs

- [x] Pick exact Programmer Dvorak keylayout variant + source → official
      Kaufmann 1.2.13 bundle, checksum-verified, vendored 2026-08-17.
- [x] Karabiner config delivery mechanism → copy-on-activation (symlink refuted
      by live test on `work`, 2026-08-15; see Phase 2).
- [x] Verify: 1Password Chrome extension ID; bash-from-nix login shell on MDM
      device. *(Resolved 2026-08-17: login-window input-menu key =
      `showInputMenu` via `CustomSystemPreferences`; Karabiner system config
      path = `/Library/Application Support/org.pqrs/config/karabiner.json`.
      Extension ID confirmed 2026-08-21.)*
- [x] Decide repo name → **`nix-macos-config`** (github.com/milesAwayAlex).

## Risk register (from the pre-mortem)

- Maintenance-to-benefit inversion → keep config boring, weekly bot PRs, graceful-abandonment design.
- macOS major releases break nix-darwin modules → never day-one upgrade macOS.
- Declared-vs-actual drift (System Settings clicks) → periodic re-read; partial coverage is honest.
- MDM conflict (work machine) → Phase 0 gate.
- Eval is single-threaded upstream → irrelevant at this repo's scale; Determinate
  Nix is the escape hatch if a monorepo-scale flake ever hurts.
