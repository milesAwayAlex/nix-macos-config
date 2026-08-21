# Bootstrap — the irreducible manual checklist

Steps a fresh machine needs that the flake cannot do for itself. Completed
in Phase 5 from the checklist in `PLAN.md`; entries land here as the
decisions that create them are made.

## AI harness

Claude Code is appliance tier: the binary is the **native installer**, which
self-updates, and nixpkgs' `claude-code` is unfree, uncached, and lags the
running version. It is deliberately not bootstrapped by an activation script
— a login is required anyway, so a run-once install costs nothing extra and
keeps `switch` off the network.

```sh
curl -fsSL https://claude.ai/install.sh | bash   # → ~/.local/bin/claude
claude   # then sign in
```

`~/.claude/settings.json` stays **unmanaged**. The harness rewrites it in
place (model, theme, plugin state), and unlike `karabiner.json` — unchanged
for years — it is still churning, so converge-copy would fight the tool
rather than protect a stable artifact. Revisit if it settles.

## Homebrew

Not a manual step any more — nix-homebrew installs the prefix on the first
switch (D16). One case still needs a hand: Homebrew refuses to install an
app-bundle cask over an existing `/Applications/<App>.app` it did not put
there. It aborts, and `brew bundle` fails the activation with it. On a machine
that predates this config, adopt those apps once, before the first switch:

```sh
brew install --cask --adopt google-chrome 1password
```

Pkg-based casks (Karabiner) have no such check; they just re-run the
installer.

### Karabiner-Elements

The cask runs the official pqrs `.pkg`, which installs a DriverKit system
extension and three privileged daemons. Two approvals no configuration can
grant, both one-time:

1. **System Settings → General → Login Items & Extensions → Driver
   Extensions** — enable `Karabiner-VirtualHIDDevice`.
2. **System Settings → Privacy & Security → Input Monitoring** — allow
   `karabiner_grabber` and `karabiner_observer`.

Do the first install from the machine's own keyboard. The installer bounces
the daemons, so remapping stops for a few seconds — which is a bad surprise
over a remote session where the remapped keyboard is the only input.

Config comes from the repo either way: `modules/home/karabiner` owns
`karabiner.json` (D2), and `modules/darwin/input` copies it to the pre-login
path so the login window is remapped too.

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
instead. Off only means that path would ask for the account password rather
than a fingerprint; it disables nothing.

The same enrollment backs 1Password's biometric unlock and, through it, `op`.

Check it from **inside tmux** once the switch has gone in — `sudo -k && sudo -v`
should raise the Touch ID prompt rather than ask for a password. That path is
the entire reason `pam_reattach` is in the stack; outside tmux it would work
either way.

Touch ID never applies to the first unlock after a restart, to a session more
than 48 hours since the last unlock, after five failed reads, or over ssh. The
password is the credential underneath, and those are the moments it is asked
for.

## 1Password

The cask installs the app; the rest is a login and three switches, which live
in two different panes of the app's own settings:

1. **Security → Unlock using Touch ID.** Gates everything below — without it
   the vault, the agent's approval prompts and `op` all fall back to typing the
   account password. Needs a fingerprint already enrolled.
2. **Developer → Use the SSH agent** — creates the socket that
   `modules/home/work.nix` names as `IdentityAgent` (D19). Until it is on, ssh
   warns once and falls back to the keys on disk.
3. **Developer → Integrate with 1Password CLI** — lets `op`, which comes from
   nixpkgs, unlock against the desktop app.

Keys are made in the app, not on the machine. With no config file the agent
offers every ssh key in every unlocked vault, in an order you do not control;
`~/.config/1Password/ssh/agent.toml` narrows and orders that list, and is worth
writing once there is more than a handful, since a server stops accepting
attempts after six. It does not exist until you create it — the Developer pane
has a button — and it stays unmanaged, because it names vaults and items and
those are per-account.

## Slack

Not declared — it exists only because of the employer, and it needs an
interactive workspace login before it does anything (D17). Install from
<https://slack.com/downloads/mac> or `brew install --cask slack`.
