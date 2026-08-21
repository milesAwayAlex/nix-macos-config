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

## Slack

Not declared — it exists only because of the employer, and it needs an
interactive workspace login before it does anything (D17). Install from
<https://slack.com/downloads/mac> or `brew install --cask slack`.
