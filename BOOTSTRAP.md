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
