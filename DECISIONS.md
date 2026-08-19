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
