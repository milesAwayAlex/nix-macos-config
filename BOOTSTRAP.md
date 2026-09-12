# Bootstrap — the irreducible manual checklist

Steps a fresh machine needs that the flake cannot do for itself, in the order
they are needed. Each section says what the step is for and what fails
without it.

1. [Nix](#nix) — install it, clone the repo.
2. [Homebrew](#homebrew) — adopt apps already in `/Applications`, or the first
   switch aborts.
3. The first switch — end of the [Nix](#nix) section.
4. [Karabiner-Elements](#karabiner-elements) — two approvals, from the
   machine's own keyboard.
5. [Login shell](#login-shell) — `chsh`, once.
6. [Input source](#input-source) — log out once, add the layout.
7. [Touch ID](#touch-id) — enroll a fingerprint.
8. [1Password](#1password) — sign in, three switches.
9. [Browsers](#browsers) — sign in to Chrome; the extension pairs with the app.
10. [AI harness](#ai-harness) and [Slack](#slack) — native installers, logins.
11. [Dev VM](#dev-vm) — DEVVM.md takes over.

## Nix

The seed is [NixOS/nix-installer](https://github.com/NixOS/nix-installer), the
community fork that installs upstream Nix and keeps an uninstall receipt
(README, "Seed record"). Download the script instead of piping it: it is short,
it names the release it fetches, and reading it is the whole review. `work` was
seeded from 2.35.1; take the current release and record it in the README.

```sh
curl -sSfL -o nix-installer.sh https://artifacts.nixos.org/nix-installer
less nix-installer.sh
sh nix-installer.sh install
```

A specific release is
`https://github.com/NixOS/nix-installer/releases/download/<version>/nix-installer.sh`.
The receipt lands at `/nix/receipt.json` and `sudo /nix/nix-installer uninstall`
reverses everything. The installer appends its hook to the `/etc` shell
profiles and writes `/etc/nix/nix.conf`, flakes on; nix-darwin knows those
stock versions and adopts them, so a fresh machine needs no move-aside. Where
it does refuse, the message names the file and asks for a `.before-nix-darwin`
suffix.

Then, in a new shell — the installer's hook is not in the old one:

```sh
git clone https://github.com/milesAwayAlex/nix-macos-config && cd nix-macos-config
git config core.hooksPath .githooks   # until the managed git config takes over at the switch
```

Adopt any pre-existing casks first (next section). Then the first switch.
`darwin-rebuild` and `just` do not exist yet — both arrive with it — so build
the system from the lock and run the copy inside the result:

```sh
nix build .#darwinConfigurations.work.system
sudo ./result/sw/bin/darwin-rebuild switch --flake .#work
```

`sudo` wants the password here; Touch ID for sudo is part of what is being
installed. This switch also installs Homebrew itself and the casks. From the
second one on it is `just switch`. A new host needs its `hosts/<name>.nix` and
a `darwinConfigurations.<name>` entry, `git add`ed before any of this — flakes
do not see untracked files.

## Homebrew

Homebrew refuses to install an app-bundle cask over an existing
`/Applications/<App>.app` it did not put there. It aborts, and `brew bundle`
fails the activation with it. On a machine that predates this config, adopt
those apps once, before the first switch:

```sh
brew install --cask --adopt google-chrome 1password
```

Pkg-based casks (Karabiner) have no such check; they just re-run the installer.

### Karabiner-Elements

The cask runs the official pqrs `.pkg`, which installs a DriverKit system
extension and three privileged daemons. Two approvals no configuration can
grant, both one-time:

1. **System Settings → General → Login Items & Extensions → Driver Extensions**
   — enable `Karabiner-VirtualHIDDevice`.
2. **System Settings → Privacy & Security → Input Monitoring** — allow
   `karabiner_grabber` and `karabiner_observer`.

Do the first install from the machine's own keyboard. The installer bounces the
daemons, so remapping stops for a few seconds — which is a bad surprise over a
remote session where the remapped keyboard is the only input.

Config comes from the repo either way: `modules/home/karabiner` owns
`karabiner.json` (D2), and `modules/darwin/input` copies it to the pre-login
path so the login window is remapped too.

## Login shell

The switch registers nix's bash in `/etc/shells` (`environment.shells`); making
it the login shell is the one per-user step nix-darwin cannot do:

```sh
chsh -s /run/current-system/sw/bin/bash
```

That path is stable across generations, which is why it is not a store path.
Terminals opened afterwards get the new shell; the session's own `SHELL` changes
at the next login. If `/run` is ever broken, `/bin/bash` remains the rescue
shell — macOS's 3.2, without the repo's config, but a shell.

## Input source

The switch copies the layout to `/Library/Keyboard Layouts/Programmer
Dvorak.bundle` and turns on the login window's input menu, but macOS reads that
directory at login, so a layout added mid-session is not offered until the next
one. Log out once after the first switch, then: System Settings → Keyboard →
Text Input → Input Sources → Edit… → **+** → Others → Programmer Dvorak.
Remove U.S. or keep it beside; the input menu switches between them.

The login window offers the layout in its own input menu (top right), and
Karabiner's remap is live there too through the pre-login copy of its config.
**FileVault's pre-boot screen is neither** — EFI knows no third-party layouts,
so that password is typed in QWERTY.

## Touch ID

`modules/darwin/pam.nix` puts Touch ID into sudo's PAM stack, but **enrolling a
fingerprint is manual and per-user**: System Settings → Touch ID & Password →
Add Fingerprint, which asks for the account password. Until one exists the PAM
stack is inert and sudo simply asks for the password as before.

**Autofilling passwords** is the toggle in that pane that governs macOS' own
AutoFill path — the Passwords app, Safari, and any third-party provider
registered under General → AutoFill & Passwords, which 1Password does ship one
for. Nothing here uses that path: the Chrome extension reaches the desktop app
over 1Password's own channel and is gated by 1Password's Touch ID setting
instead. Off only means that path would ask for the account password rather than
a fingerprint; it disables nothing.

The same enrollment backs 1Password's biometric unlock and, through it, `op`.

Check it from **inside tmux** once the switch has gone in — `sudo -k && sudo -v`
should raise the Touch ID prompt rather than ask for a password. That path is
the entire reason `pam_reattach` is in the stack; outside tmux it would work
either way.

## 1Password

The cask installs the app; the rest is a login and three switches, which live in
two different panes of the app's own settings:

1. **Security → Unlock using Touch ID.** Gates everything below — without it the
   vault, the agent's approval prompts and `op` all fall back to typing the
   account password. Needs a fingerprint already enrolled.
2. **Developer → Use the SSH agent** — creates the socket that
   `modules/home/work.nix` names as `IdentityAgent` (D19). Until it is on, ssh
   warns once and falls back to the keys on disk.
3. **Developer → Integrate with 1Password CLI** — lets `op`, which comes from
   nixpkgs, unlock against the desktop app.

A fourth switch is worth taking once a key exists: **Developer → Generate SSH
config files**, which writes `~/.ssh/1Password/config` from the host URL on each
key item. `modules/home/work.nix` already includes that path, so the manual
`Include` the app asks for is not needed — but the bookmarks themselves are
per-account and made by hand, one per host.

## Browsers

Chrome is the declared browser (cask), and `modules/darwin/chrome.nix` writes
its policy at the first switch: the 1Password extension force-installed,
Chrome's own password manager and autofill off. `chrome://policy` shows the
baseline before any sign-in. What remains is per-account: sign in to the Google
Workspace profile (sync is a per-profile choice the policy leaves alone), and
let the extension pair — on its first use the 1Password app asks once to trust
the browser, and from then on the extension unlocks with the app, by Touch ID
once the switch in the [1Password](#1password) section is on. Firefox is not
installed and has no step; its declared form is in the PLAN backlog.

## AI harness

Claude Code is appliance tier: the binary is the **native installer**, which
self-updates, and nixpkgs' `claude-code` is unfree, uncached, and lags the
running version. It is deliberately not bootstrapped by an activation script — a
login is required anyway, so a run-once install costs nothing extra and keeps
`switch` off the network.

```sh
curl -fsSL https://claude.ai/install.sh | bash   # → ~/.local/bin/claude
claude   # then sign in
```

`~/.claude/settings.json` stays **unmanaged**. The harness rewrites it in place
(model, theme, plugin state), and unlike `karabiner.json` — unchanged for years
— it is still churning, so converge-copy would fight the tool rather than
protect a stable artifact. Revisit if it settles.

## Slack

Not declared — it exists only because of the employer, and it needs an
interactive workspace login before it does anything (D17). Install from
<https://slack.com/downloads/mac> or `brew install --cask slack`.

## Dev VM

`just devvm-up` and everything after it — the seed boot, the first
`just devvm-rebuild`, `just devvm-adopt` — is [DEVVM.md](DEVVM.md), "Bootstrap".
