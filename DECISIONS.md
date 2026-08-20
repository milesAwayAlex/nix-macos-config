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
cert exports (Aikido) and parked per-machine tooling (nvm, gcloud, deno,
Spacelift-after-rotation, Postgres PATH). Secrets never go in managed shell
files; ambient-env secrets move to 1Password wiring when that step lands.

**Why.** Same split as D9, adapted: bash has no native two-global-files
mechanism, so the hook provides one. Aikido rewrites shell rc files in
place (observed 2026-08-18) — HM ownership without a hook would either lose
those writes or clobber-loop.

**Known failure mode.** Aikido updates target `.bashrc`/`.profile` directly;
against HM's read-only symlinks that fails or replaces the link. The next
`just switch` then complains ("existing file in the way") — the fix is
moving the fresh Aikido block into `~/.bashrc.local` and re-switching.

**Revisit when.** Aikido's write behavior turns out to be more aggressive
than observed, or the 1Password/secrets step re-homes the parked tooling.

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

**Why.** The managers were not being used as managers. Every `.nvmrc` under
`~/code` said `v22` while nvm carried three unused majors; gcloud sat at
463.0.0 from 2024-02, and the `kubectl` it dispatched was 1.27 against 1.35
control planes — an eight-minor skew that kubectl itself warned about on
every call. An imperative updater only helps if someone runs it, and nobody
does; the weekly lock bump is the update ritual that actually happens. The
genuine per-repo variance turned out to be pnpm (7.33 / 9.15 / 10.10 via
`packageManager`), which corepack resolves from the repo itself and needs no
manager at all.

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
