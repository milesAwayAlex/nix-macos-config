# Decisions

Operating conventions for this repo, ADR-lite: one numbered entry per
decision — **Decision / Why / Revisit when**. Append new entries; supersede an
old one by striking it through and pointing at its replacement, never by
deleting. The principles behind the whole endeavor live in [PLAN.md](PLAN.md);
this file is the durable "how".

## D1 — Activation scripts: tool sourcing *(2026-08-18)*

**Decision.** Comparison tools are store-pinned — `${pkgs.diffutils}/bin/cmp`
for single files, `${pkgs.diffutils}/bin/diff -rq` for directory trees.
POSIX-universal basics (`mkdir`, `cp`, `rm`, `install`) ride the activation
PATH bare. Exported modules must be self-contained: no `/usr/bin` paths, no
PATH assumptions beyond the basics.

**Why.** `/usr/bin` tools are unpinned (Apple changes them between macOS
releases) and absent on Linux, which `modules/home/` may serve later. Store
paths are locked by the flake — identical bytes on every host, forever, until
a deliberate lock bump.

**Revisit when.** A module needs a tool whose closure cost actually matters,
or `modules/home` lands on a non-nix host.

## D2 — Managed config files: symlink first, converge-copy as fallback *(2026-08-15)*

**Decision.** Home-manager store symlinks are the default delivery for managed
files. When the consuming app mishandles symlinks, fall back to
copy-on-activation guarded by an equality check. Converge semantics: the repo
copy is canonical; drift in the live file is overwritten on every switch (with
a message in the output); the guard keeps no-op switches genuinely no-op.

**Why.** Karabiner, by live test: its file watcher misses edits made through a
symlink, and GUI writes replace the link with a plain file. The equality guard
preserves the idempotence gate and avoids needless app reloads.

**Revisit when.** A managed file needs bidirectional editing (then
`mkOutOfStoreSymlink` or a different ownership story per file).

## D3 — Module layout: host identity vs. portable policy *(2026-08-15)*

**Decision.** Host identity (`nixpkgs.hostPlatform`, `system.primaryUser`,
the user's home, `system.stateVersion`) lives in `hosts/<alias>.nix`. Portable
policy lives in `modules/darwin/` and `modules/home/`. Policy numbers a host
may reasonably tune are set with `lib.mkDefault`.

**Why.** `stateVersion` is per-host by definition (set once at that host's
first install); usernames can differ; shared policy in one place prevents
copy-paste drift, and `mkDefault` keeps a host override one plain assignment
away.

**Revisit when.** A third host class appears (Linux metal/VM) and the split
needs another layer.

## D4 — Garbage collection: scheduled + reactive, never bare `-d` *(2026-08-15)*

**Decision.** Two mechanisms: scheduled (`nix.gc.automatic` weekly with
`--delete-older-than 14d`, plus weekly store optimise) and reactive
(`nix.settings.min-free` 10 GiB / `max-free` 20 GiB). Manual GC goes through
`just gc`, which encodes the same `--delete-older-than 14d` form. Bare
`nix-collect-garbage -d` is banned.

**Why.** The schedule keeps things tidy; the reactive floor is what actually
prevents disk-full mid-operation (a real past incident). Bare `-d` deletes all
previous generations — the rollback story.

**Revisit when.** Disk-pressure patterns change (large local builds,
`nix.linux-builder`).

## D5 — Vendored third-party artifacts require provenance *(2026-08-17)*

**Decision.** Any third-party artifact vendored into the repo gets a
provenance chain: fetch the official distribution, verify a pinned checksum
(vendor- or Homebrew-published), diff against any locally installed copy, and
record the chain in a comment at the vendoring site.

**Why.** The repo is public; "reviewable beats clever" extends to bytes we
redistribute. Precedent: Programmer Dvorak 1.2.13 bundle (sha256
`842ffaf…006`, chain recorded in `modules/darwin/input/default.nix`).

**Revisit when.** An artifact can't be checksum-chained — then reconsider
vendoring it at all.

## D6 — Update model: release train, matched sets, deliberate pulls *(2026-08-15)*

**Decision.** nixpkgs rides the stable release train as a matched set
(`nixpkgs-XX.YY-darwin` + `nix-darwin-XX.YY` + home-manager `release-XX.YY`),
bumped together roughly twice a year. Machines consuming this repo's modules
as a flake input pull updates deliberately (`nix flake update
nix-macos-config` + rebuild), never automatically.

**Why.** Boring beats fresh for machine config; matched sets avoid the classic
nixpkgs/nix-darwin version-mismatch footgun; deliberate pulls mean no surprise
keyboard behavior mid-week.

**Revisit when.** A forced macOS update needs master-only nix-darwin fixes
(escape hatch: flip to unstable, three input lines), or package freshness
hurts in Phase 4 (surgical secondary unstable input).

## D7 — Git hooks: versioned in-repo, activated per clone *(2026-08-15)*

**Decision.** Hooks live in `.githooks/` under version control and are
activated once per clone with `git config core.hooksPath .githooks`. Hook
scripts must work without repo tooling on PATH (the gitleaks hook falls back
to `nix run` with a hardcoded `/nix/var/nix/profiles/default/bin/nix` for
non-interactive shells). CI re-runs the same scan as a backstop.

**Why.** `.git/hooks` is never transmitted by design; versioning the hook and
paying one activation line per clone gets every machine protected by the same
reviewed script. The PATH-independence covers GUI git clients and tool
harnesses.

**Revisit when.** Phase 4's `programs.git` includeIf makes the activation
declarative, or a hook needs ordering/multiplexing.

**Update 2026-08-18.** Activation is now declarative on HM-configured
machines: a `hasconfig:remote.*.url` include in `modules/home/git.nix` sets
`core.hooksPath` for any clone of this repo (D9). The manual `git config`
line remains only for machines without this HM config. The versioned-hooks
convention itself stands.

## D8 — Flake module exports named by module class *(2026-08-18)*

**Decision.** Exported module outputs are named after the module class they
target: `homeModules.*` (home-manager) and `darwinModules.*` (nix-darwin),
mirroring upstream's `nixosModules.*`. `homeManagerModules` is the legacy
spelling this repo migrated from.

**Why.** The class convention names the platform, not the implementing tool
(nobody writes `nixDarwinModules`). Our pinned home-manager release documents
`homeModules`, and flake-parts defines it as a typed option — the direction of
travel. Verified 2026-08-18 that no tooling on our train treats either
spelling specially (`nix flake show` marks both `unknown`), so the rename cost
was purely the one consumer, coordinated at its next input bump.

**Revisit when.** Nix's known-outputs list or the HM ecosystem blesses a
different name.

## D9 — Git global config: HM owns the XDG file, `~/.gitconfig` is the machine's *(2026-08-18)*

**Decision.** Declarative git config lives in `~/.config/git/config`
(`programs.git`). `~/.gitconfig` is deliberately unmanaged — reserved for
machine-local and IT/EDR-pushed entries (on `work`: Aikido's
`http.sslCAInfo`). Git reads it after the XDG file, so its keys override
ours by design.

**Why.** IT tooling rewrites `~/.gitconfig` (observed 2026-08-17); managing
that file declaratively would be a tug-of-war. The two-file split gives HM
full ownership of one file and the machine full ownership of the other,
with a defined precedence.

**Revisit when.** An IT-pushed key starts overriding something we care
about (then: contest it per-repo with local config, or negotiate with IT).

## D10 — Shell config: HM owns the bash files, `~/.bashrc.local` is the machine's *(2026-08-18)*

**Decision.** `programs.bash` owns `.bashrc`/`.bash_profile`/`.profile`/
`.bash_logout`. The last line of the managed bashrc sources
`~/.bashrc.local` if present — an unmanaged, machine-local file for IT/EDR
cert exports (Aikido) and anything one machine alone needs on PATH. Secrets
never go in managed shell files; ambient-env secrets move to 1Password wiring
when that step lands.

**Why.** Same split as D9, adapted: bash has no native two-global-files
mechanism, so the hook provides one. Aikido rewrites shell rc files in
place (observed 2026-08-18) — HM ownership without a hook would either lose
those writes or clobber-loop.

**Known failure mode.** Aikido updates target `.bashrc`/`.profile` directly;
against HM's read-only symlinks that fails or replaces the link. The next
`just switch` then complains ("existing file in the way") — the fix is
moving the fresh Aikido block into `~/.bashrc.local` and re-switching.

**Revisit when.** Aikido's write behavior turns out to be more aggressive
than observed, or the 1Password/secrets step re-homes what the hook carries.

## D11 — Out-of-nixpkgs vim plugins ride flake inputs *(2026-08-19)*

**Decision.** Vim plugins deliberately kept outside nixpkgs (first:
yegappan/lsp) are consumed as `flake = false` inputs and built inside the
module with `vimUtils.buildVimPlugin`. The module stays a regular path
export (`homeModules.vim`) and takes the plugin source as a module arg;
each consuming flake supplies it via home-manager's `extraSpecialArgs`
(`vim9-lsp = inputs.vim9-lsp;`). A consumer of the export reaches the
exact pinned source transitively — on `old`:
`inputs.nix-macos-config.inputs.vim9-lsp`. Bumping is `just update
vim9-lsp`.

**Why.** `flake.lock` is already this repo's pinning mechanism: the same
deliberate update ritual as the release train, no fetchFromGitHub
rev-and-hash surgery. Staying out of nixpkgs is a feature here — full
control over the version of the plugin that defines the editing
experience, decoupled from the D6 release train. A wrapper-module export
(closing over the input via `_module.args`) was tried first and worked,
but made vim a special case among otherwise-uniform path exports; one
visible arg line per consumer is more transparent than one invisible
wrapper.

**Revisit when.** The plugin lands in nixpkgs (upstreaming intent noted in
PLAN, after the dust settles), `old` is adopted into this flake (Phase 6 —
both futures are intended), or the pattern multiplies — several
arg-taking modules would argue for an overlay instead.

## D12 — Runtimes and cloud CLIs are declared, not version-managed *(2026-08-20)*

**Decision.** Language runtimes and vendor CLIs come from nixpkgs at a
pinned attribute (`nodejs_22`, `kubectl`, `google-cloud-sdk`), and the
imperative version manager in front of them is retired — nvm first, with
`tfswitch`/`pyenv`/`jenv` to follow as those toolchains land. Where a tool
has its own plugin mechanism that writes into its install directory
(`gcloud components install`), the components move into the derivation
(`withExtraComponents`). Per-project divergence is the exception and is
handled at the project boundary: `nix shell nixpkgs#nodejs_20` for a
one-off, dev shells + direnv if it becomes routine.

**Why.** The managers were not being used as managers — the pinned versions
went stale by years and the dispatched `kubectl` drifted eight minors from
the control planes it talked to. An imperative updater only helps if someone
runs it, and nobody does; the lock bump is the update ritual that actually
happens. The one genuine per-repo variance is pnpm, and `packageManager`
already encodes it: the packaged launcher re-execs whatever a repo names, so
no manager is needed for that either.

**Revisit when.** A repo pins a node major the pinned one cannot satisfy
(then: dev shell, not nvm), or a vendor CLI ships a component that nixpkgs
does not carry.

## D13 — Config a tool rewrites at runtime stays the tool's *(2026-08-20)*

**Decision.** HM manages config files their program only reads. Files the
program itself rewrites during normal use are left alone unless the file is
stable in practice and worth the converge-copy machinery (D2). First
refusal: `~/.claude/settings.json` — the harness writes model, theme and
plugin state into it. Same reasoning keeps `~/.npmrc` unmanaged (npm writes
registry auth tokens there; the global prefix is set by env var instead) and
`~/.config/gh/hosts.yml` unmanaged while `config.yml` is declared.

**Why.** Three ownership models are now in play — read-only store symlink,
converge-copy (D2), and machine-local (D9/D10) — and the deciding question
is not how important the file is, it is who writes it. A symlink to the
store makes the program's own writes fail; converge-copy makes them silently
vanish at the next switch. Karabiner earns converge-copy because the config
has not changed in years and the GUI is the only writer; a harness that
rewrites settings whenever a model or theme is picked would be fighting the
tool for no gain.

**Revisit when.** The file stops churning (then converge-copy), or the tool
grows a split between declared and runtime state.

## D14 — Packages nixpkgs lacks are written as upstreamable derivations *(2026-08-20)*

**Decision.** A package nixpkgs does not carry (first: `kube-fzf`) gets a
normal nixpkgs-shaped expression under `packages/`, pinned with
`fetchFromGitHub` + hash, exposed as `packages.${system}.<name>` and pulled
into modules with `callPackage`. Deliberately *not* the D11 pattern: flake
inputs are for sources whose updates we want to ride, `packages/` is for
things whose destination is a nixpkgs PR — the file should already be
`pkgs/by-name/ku/kube-fzf/package.nix` with nothing but the path changed.

**Why.** The two cases pull in opposite directions. yegappan/lsp is alive and
defines the editing experience, so `just update vim9-lsp` is the point;
kube-fzf's last commit is 2023-09 and there is nothing to track, so a flake
input would add lock churn plus a rev that has to be translated back into a
`fetchFromGitHub` block at upstreaming time. Writing the derivation in its
final shape means the PR is a file move and the local copy is the test.

**Revisit when.** The package lands in nixpkgs (then delete the file and the
`callPackage`), or a `packages/` entry starts needing head-tracking — that is
a D11 case wearing the wrong hat.

## D15 — GNU userland, unprefixed *(2026-08-20)*

**Decision.** `coreutils`, `findutils`, `gnused`, `gnugrep`, `gawk`,
`gnutar`, `diffutils` and `gnumake` go into `home.packages` under their
plain names, so `ls`, `sed`, `find`, `awk`, `grep`, `tar`, `make` resolve to
GNU in any interactive shell and anything it spawns. No `g`-prefix, no
`gnubin`-style opt-in directory. `uutils-coreutils` rejected — a Rust
reimplementation buys nothing here and adds compatibility unknowns.

**Why.** The work is GKE, helm and CI — Linux and GNU end to end — and the
BSD/GNU differences are binary rather than gradual: `sed -i` versus
`sed -i ''`, `date -d` versus `date -v`, `stat -c` versus `stat -f`, plus
`find -printf`, `xargs -r`, `grep -P` and `sort -h` simply absent. The
failure modes are asymmetric, which decides it: GNU tools fed a BSD idiom
error loudly, while BSD tools fed a GNU idiom copied from Linux docs produce
wrong output silently. Staying on BSD meant keeping the quieter failure.
Two tools macOS has no equivalent for — `timeout` and `realpath` — come
along free, and `make` jumps from 3.81 (2006) to 4.4.

**Scope and cost.** Only the user profile changes; the system stays BSD, so
launchd jobs and absolute `/usr/bin/…` calls are unaffected — a script that
works in the shell can still differ under launchd. One real breakage,
handled in the same change: `ls -G` is colour on BSD and `--no-group` on
GNU, so `modules/home/bash` now aliases `ls --color=auto`. `findutils` also
shadows macOS `locate`, whose database GNU `updatedb` does not maintain.

**Revisit when.** Something outside the shell turns out to depend on BSD
behaviour — reverting is deleting one module.

## D16 — Homebrew is the appliance tier: casks only, self-updating only *(2026-08-20)*

**Decision.** `homebrew.casks` carries GUI applications that update
themselves; everything else comes from nixpkgs. A cask is admitted only if
`brew info --json=v2` reports `auto_updates: true` — a cask that does not
self-update is a frozen copy either way, and nix at least moves it on a
deliberate `nix flake update`. No formulae, no taps, no `masApps`.
`onActivation` is `autoUpdate = false`, `upgrade = false`, `cleanup = "none"`.
nix-homebrew owns the installation, so Homebrew itself is declared too.

**Why.** Three properties keep these apps out of the store, and none of them
is about the package manager. TCC grants and code-signature checks key on the
real `/Applications` path, so 1Password's browser integration and Karabiner's
Input Monitoring break when the bundle moves; the apps ship their own
updaters, which cannot write to a read-only store; and a browser is the last
thing that should sit at whatever version a flake was locked to. The
admission rule falls out of that — self-updating is the *reason* to use a
cask, so a cask that does not self-update has no argument left.

**Scope and cost.** nix-darwin only renders a Brewfile and shells out to
`brew bundle`; it does not install Homebrew, and nothing brew installs is a
store path. So: no rollback (`--rollback` restores the Brewfile, not the
software), no GC, no offline switch, no dedupe against `home.packages`.
Declared versions are meaningless by construction — the Brewfile is a list of
names, brew's recorded version goes stale as each app updates itself, and
`--upgrade` skips `auto_updates` casks anyway (only `--greedy` reaches them).
`autoUpdate` stays off so a switch never depends on what the tap says today.

**On `cleanup`.** `"uninstall"` is wanted eventually — it is the only drift
detector available here, and without it deleting a line from this file does
nothing on an already-configured machine. It is off because `work` still
carries a pre-nix Homebrew of 110 formulae, and cleanup would take all of
them. Flip it after the Phase 5 purge. Two limits to remember when it goes
on: it sees only brew's own receipts, so manually installed apps (Docker,
Rancher Desktop) are invisible to it, and `"zap"` deletes configuration and
data, not just binaries.

**Why nix-homebrew.** Homebrew cannot be a nix package — it is a
self-modifying git checkout that owns a prefix and writes Cellar, Caskroom
and receipts into it at runtime, so a read-only store path cannot host it.
nixpkgs accordingly has no `brew`. nix-homebrew does not package it either:
it clones `Homebrew/brew` from a flake input into the prefix, which pins
brew's own version in `flake.lock` and moves it on `nix flake update`. That
buys the one thing nothing else can — a fresh machine with no curl-bash step
— and it supplies Ruby from nixpkgs instead of brew's portable download.
The cost is an input outside the release train, and `autoMigrate` on any
machine that already has a prefix. Rejected first on the strength of the tap
argument, which turned out to be the wrong axis; the install step was always
the real question. `enableRosetta = false`.

**Taps are structurally impossible, not merely undeclared.**
`mutableTaps = false` with nothing declared makes nix-homebrew point
`$HOMEBREW_LIBRARY/Taps` at an empty store path, so `brew tap` cannot write —
the same class of guarantee as the store being read-only, rather than a rule
that has to be remembered. It also exports `HOMEBREW_NO_AUTO_UPDATE=1`, which
closes a real gap: `onActivation.autoUpdate = false` governs the switch only,
so a manual `brew install` could still pull an update. The API path is
unaffected, because `HOMEBREW_NO_INSTALL_FROM_API` is set only when
`homebrew/homebrew-core` is declared — verified in the built launcher, which
carries `NO_AUTO_UPDATE` and not `NO_INSTALL_FROM_API`.

What this costs is trying a tapped tool by hand. Little, now that `nix shell
nixpkgs#foo` is the ad-hoc path and leaves nothing behind, and all twelve taps
this machine carried were CLI tools of the kind that now come from nixpkgs. A
tap that is genuinely needed is a flake input plus a `taps` entry plus a
`trust.taps` entry — the correct declarative outcome anyway.

**Migration gotcha.** `autoMigrate` deletes only the git-*tracked* files of
the brew checkout; Cellar, Caskroom, bin and `Library/Taps` are ignored state
and survive. So taps are not cleared by adoption, and because `is_occupied`
fires on existence rather than contents, even an emptied `Library/Taps`
directory aborts activation under `mutableTaps = false`. It has to be removed
outright — nix-homebrew's own CI does exactly that before its declarative-tap
test.

**On brew as a throwaway.** Considered and rejected: install the casks at
activation and discard brew afterwards. It does not work, because brew's
memory of what is installed *is* the prefix. Discard it and the next switch
tries to install Chrome again, and `brew install --cask` aborts when the app
already exists at its `/Applications` path — so every switch after the first
would fail. Uninstall and upgrade stanzas live there too. The honest version
of that idea is to drop the declaration and list the three apps in
`BOOTSTRAP.md` by hand, which trades the reproducible list for nothing but
one fewer input.

**On third-party taps.** Losing them costs nothing because they had already
stopped working: Homebrew 6.0 enables `HOMEBREW_REQUIRE_TAP_TRUST`, under
which an untrusted tap will not load and aborts the switch that needs it.

**Revisit when.** An app we want stops self-updating — then it belongs in
nixpkgs, not here.

## D17 — Employer-specific tooling is its own module *(2026-08-20)*

**Decision.** Tools that exist only because of the employer's platform
choices live in `modules/home/work.nix` (first: `spacectl`, `spicedb`), not
in `pkgs.nix` or a topic module. Applications in the same category — Slack —
are a `BOOTSTRAP.md` line rather than a cask.

**Why.** These modules are consumed by other flakes (D8), and the personal
machine has no Spacelift stack and no reason to install a permissions
database. Mixing them into `pkgs.nix` would make the shared staples list
untakeable as a whole. The split also survives a job change as a single
file deletion.

**Why Slack is not a cask.** It is the one app in the set whose presence is
entirely a function of employment, and it needs an interactive login on a
company workspace before it does anything — so declaring it saves nothing a
bootstrap line does not, and it would put a company dependency in the
system layer that a consumer of these modules cannot decline.

**Revisit when.** The list grows past a handful, or a second employer-shaped
context appears — then it wants a directory and a naming scheme, not one file.

## D18 — Unfree packages by name, never by blanket *(2026-08-20)*

**Decision.** `nixpkgs.config.allowUnfreePredicate` matches an explicit list
of package names, declared in `hosts/work.nix` next to the module whose
packages need it.
`allowUnfree = true` is not used, and `NIXPKGS_ALLOW_UNFREE` is not the
mechanism. First and only entry: `1password-cli`.

**Why.** Unfree is not one property — it spans "vendor binary, freely
redistributable" and "licence forbids redistribution", and the difference
matters on a public repo. A blanket flag decides all future cases in advance
and silently; a list makes each one a diff with a comment next to it. The
cost is one line per package, paid at the moment there is a reason to think
about it.

**Where it lives.** The system layer, and not by choice: nix-darwin and
home-manager are separate `evalModules` calls, and `useGlobalPkgs = true`
drops HM's `nixpkgs.*` module entirely (`useNixpkgsModule = !useGlobalPkgs`),
so `nixpkgs.config` is not an option a home module can set. Given that, the
predicate sits in `hosts/work.nix` alongside the `home-manager.users.alexm`
import that pulls in the package — the closest the two layers can get. A
consumer taking `homeModules.work` from elsewhere needs their own predicate;
the README says so.

**On `op` specifically.** The `1password-cli` cask is not `auto_updates`, so
it fails D16. nixpkgs extracts AgileBits' own `op` from their signed pkg and
sets `dontStrip` on darwin, so the signature survives relocation into the
store — verified: identifier `com.1password.op`, team `2BUA8C4S2C`,
`codesign -v` clean. That is what the desktop app checks before allowing
biometric unlock, so the integration is unaffected by where the binary sits.
The version lag against the cask (2.34.0 vs 2.39.0) is the price of a pinned
tool that moves on a deliberate `nix flake update`.

**Revisit when.** An entry turns out to be redistribution-restricted in a way
that matters for a public repo, or the list grows past the point where one
comment each is readable.

## D19 — The ssh agent is the password manager's, one per machine *(2026-08-20)*

**Decision.** Private ssh keys live in a password manager and are reached
through its agent socket rather than as files on disk. `work` uses 1Password,
named by `IdentityAgent` under `Host *` in `modules/home/work.nix` — the
company's manager, so it sits with the rest of the employer-coupled config
(D17). The personal machine gets Bitwarden the same way when it is ported.
Keys already on disk stay until each is re-created in a vault.

**Why `IdentityAgent` and not `SSH_AUTH_SOCK`.** The directive is per-host, so
a second manager is a named block rather than a fight over one inherited
environment variable, and macOS' own launchd agent stays the default for
anything not named. `Host *` says the quiet part: a machine has one of these.

**The value has to carry its own quotes.** The socket path contains a space
and home-manager renders directives verbatim. Unquoted, ssh does not skip the
line — it rejects the entire config file (`extra arguments at end of line`,
then `terminating`), so every ssh on the machine breaks at once. A socket that
does not exist yet is the benign case: a warning, then fall-through to the
on-disk keys.

**Signing is a different mechanism, not a second host.** `gpg.format = ssh`
makes git shell out to `ssh-keygen -Y sign`, which reads `SSH_AUTH_SOCK` and
never parses `ssh_config` — so `IdentityAgent` cannot scope it. 1Password's
answer is `op-ssh-sign` in the app bundle, pointed at by `gpg.ssh.program`,
which bypasses the agent entirely. Nothing is configured yet: commits from
this repo carry the personal identity, so the signing key belongs in the
personal manager and lands with Bitwarden.

**Bookmarked hosts are delegated, not described.** 1Password generates
`~/.ssh/1Password/config` from a host-URL field on each key item — a
`Match Host … User …` block per bookmark that pins `IdentityFile` to that
key's public half under `IdentitiesOnly`, which is the real answer to a
server's six-attempt limit. The repo declares the `Include` and nothing else.
Describing those blocks here instead would copy vault contents into a public
repo and go stale on every key change. The cost is that the pinning is
machine-local state: on a machine where the bookmarks have not been recreated
the `Include` resolves to nothing and ssh goes back to offering every key.
Graceful, but not a guarantee the flake can make.

**Revisit when.** Two managers hold keys on one machine — then `Host *`
becomes the personal default and work hosts get named blocks.
