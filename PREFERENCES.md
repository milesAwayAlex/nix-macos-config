# macOS preferences

The declared set lives in `modules/darwin/preferences.nix`; `prefs-status`,
built by the same module, reads every key back out of its real domain and
reports drift. This is the operating manual for both.

## Write-only, and everything that follows

nix-darwin emits one `defaults write` per non-null key at activation and never
reads anything back. Four consequences, and they drive every procedure below:

- **Deleting a line does not revert anything.** It stops the write; the last
  value written stays on the machine forever.
- **Nothing is enforced between switches.** System Settings can change any
  declared key freely and the machine will look fine until the next switch.
- **A declared key is not a set key.** Until you switch, it is an intention.
- **`/Library/Managed Preferences/` outranks all of it.** An MDM profile wins
  over anything written here, silently.

The tool exists because of the second point: the configuration cannot tell you
whether the machine agrees with it, so something has to go and look.

## Two copies of prefs-status

Knowing which one you are running is most of the skill:

| | built from | answers |
|---|---|---|
| `result/sw/bin/prefs-status` | the **candidate** config, after `just build` | what a switch *would* change |
| `prefs-status` / `just prefs-status` | the **running** generation | drift since the last switch |

Same program, different declared set baked in at build time. The PATH copy
appears at the first switch that includes this module. Both only ever call
`defaults read`, so running either is safe at any moment; the exit status is
non-zero on drift.

## Dry-run ladder

Cheapest first. Only the last line touches the machine:

    just check     # eval only, seconds, no sudo — this is where the assertion fires
    just build     # full build, no sudo, leaves ./result
    result/sw/bin/prefs-status
    diff <(grep -o "defaults write [^ ]* [^ ]*" /run/current-system/activate | sort) \
         <(grep -o "defaults write [^ ]* [^ ]*" result/activate | sort)
    just switch
    prefs-status   # expect: 0 drifted

The `diff` is the honest preview: it lists the exact writes activation will
add, drop or move, which is a stronger statement than the drift count because
it covers keys the tool does not (`CustomUserPreferences` lists, say).

## Adding a key

Find the option, then let the build tell you the rest:

    # every key in a group
    nix eval --json .#darwinConfigurations.work.options.system.defaults.finder \
      --apply builtins.attrNames

    # what it does, and what it accepts
    nix eval --raw .#darwinConfigurations.work.options.system.defaults.finder.ShowPathbar.description
    nix eval --raw .#darwinConfigurations.work.options.system.defaults.finder.NewWindowTarget.type.description

    # what the machine holds now
    defaults read com.apple.finder ShowPathbar

The `.options.` path works for any nix-darwin or home-manager option and
survives version bumps, which grepping the store source does not. `man 5
configuration.nix` is the offline equivalent.

Then add it to the matching `system.defaults.<group>` block and run
`just check && just build && result/sw/bin/prefs-status`. Two things to read
off the result:

- **The assertion fires** if the group is not in `targets`. The message names
  the `<domain> <key>`; the fix is one line. See below.
- **The new key reports `ok` before you switch** — the machine already had
  that value. Harmless, but the key buys nothing except protection against a
  future change, which is sometimes the point and sometimes noise.

### Declared value vs. what the plist holds

`prefs-status` compares the post-`apply` value, so hand-checking a key with
`defaults read` shows the plist form rather than what you wrote:

| declared | plist holds |
|---|---|
| `controlcenter.*` bool — except `BatteryShowPercentage`, a plain bool | `18` shown, `24` hidden |
| `hitoolbox.AppleFnUsageType` string | `0`–`3` |
| `finder.NewWindowTarget` string | four-char code (`PfHm`, `PfDe`, …) |
| a float | must be a native float; a string throws at eval |

## Removing a key

The subtle one, because deleting the line is never the whole job. Decide which
of three things you want:

**1. Revert to a different value** — the usual case. Set the opposite value,
switch, and only then drop the line in a later commit if you no longer want it
declared:

    # edit the value, not the presence of the line
    just switch && prefs-status

**2. Unset it entirely** so the app falls back to its own compiled-in default,
which is often not a value you can write. `defaults delete` is the only way
there, and nix-darwin has no mechanism for it:

    defaults delete -g AppleInterfaceStyle                  # NSGlobalDomain
    defaults delete com.apple.dock static-only              # app domain
    defaults delete ~/Library/Preferences/ByHost/com.apple.controlcenter Bluetooth
    sudo defaults delete /Library/Preferences/com.apple.loginwindow showInputMenu

Remove the declaration in the same change, or the next switch writes it
straight back. `AppleInterfaceStyle` is the standing example: its type accepts
only `"Dark"`, so there is no declarative light mode and going back is a
delete by hand.

**3. Stop managing it, keep the value.** Just delete the line — but know what
you are buying: the value persists unenforced, and the tool stops reporting on
it, so that key can drift from then on with no signal at all. Prefer 1 or 2
unless you genuinely mean "I no longer care".

Dropping the last key of a group leaves its `targets` entry unused, which is
harmless — an entry for a group with no declared keys contributes to neither
side of the assertion. Dropping the last `dock.*` key also stops activation
restarting the Dock.

## When a change doesn't appear

| changed | takes effect |
|---|---|
| any `dock.*` | activation restarts the Dock itself |
| `finder.*` | `killall Finder` |
| `controlcenter.*`, `menuExtraClock.*` | `killall ControlCenter` |
| `hitoolbox.AppleFnUsageType` | restart |
| `spaces.spans-displays`, icon appearance | logout |
| most `NSGlobalDomain` keys | next launch of the app that reads it |

nix-darwin never runs `activateSettings`, which is what System Settings uses to
make global changes land without a logout. It can be invoked by hand:

    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u

In all these cases `prefs-status` reports `ok` already — the plist is written;
it is the reader that hasn't noticed.

## Crossing a nix-darwin version

Inputs move as a matched release-train set, all three together (D6):

    just update nixpkgs nix-darwin home-manager
    just check                                     # removed options -> eval error, named
    just build 2>&1 | grep -i "obsolete\|renamed\|deprecated"
    result/sw/bin/prefs-status                     # the regression test

The last line is the point. On a **settled** machine — one where the running
`prefs-status` already says `0 drifted` — building the new nix-darwin and
running *its* copy of the tool before activating should also say `0 drifted`,
because nothing on disk has changed. Any drift there is upstream moving
underneath the config: a domain that relocated, or a value encoding that
changed. That is precisely the class of rot the assertion cannot see, and this
catches it for the price of one command.

If the machine is not settled first, the signal is noise. Settle it, then bump.

Renames arrive as build *warnings* rather than errors and scroll past easily,
hence the grep; `dock.expose-group-by-app` is the one already handled, in
`aliases`.

## When the assertion fires

`targets` is the one place the module restates something upstream owns — which
domains `defaults` is handed for each option group. It is checked against the
`defaults write` lines nix-darwin actually emits, so a divergence fails
`just check` instead of quietly producing a wrong answer:

    preferences.nix: `targets` no longer matches nix-darwin's writes.
      written, never checked: com.apple.WindowManager EnableStandardClickToShowDesktop
      checked, never written: com.apple.Dock autohide

- **written, never checked** — a group is missing from `targets`, or upstream
  added a second domain for one. Add the entry. This is the failure that used
  to be silent: those keys were being written and never verified.
- **checked, never written** — the entry is wrong, or the option no longer
  exists. Correct the domain, or drop the key.

A broken match can only produce a mismatch, never a false pass, so the check
fails safe: if upstream ever changes the shape of those activation lines, every
key reports as unwritten rather than nothing reporting at all.

## When a key drifts and shouldn't

In rough order of likelihood:

1. **An MDM profile owns it.** Managed preferences outrank the write and it
   loses silently. Check both layers:

       defaults read "/Library/Managed Preferences/<domain>" <key>
       defaults read "/Library/Managed Preferences/$USER/<domain>" <key>

2. **A running app rewrote it.** Dock, Finder and System Settings write their
   in-memory state back on quit, so a change made through the UI after a
   switch wins until the next one.
3. **The value encoding is wrong** — see the table above. The tool would
   report drift on a machine that is actually correct.
4. **A `CustomSystemPreferences` key drifts forever.** Its attribute name is
   handed to `defaults write` verbatim by a **root** activation script, so a
   bare `com.apple.loginwindow` lands in `/var/root/Library/Preferences/`
   rather than `/Library`'s. Full paths are mandatory under that tree; this
   was a live bug the tool found on its first run.
