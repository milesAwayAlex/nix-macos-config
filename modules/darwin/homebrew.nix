# Homebrew is the appliance tier: signed GUI apps that update themselves and
# want a real /Applications path for TCC, Spotlight and the Dock (D16). Tools
# come from nixpkgs.
#
# Two modules, doing different jobs. nix-homebrew owns the *installation* —
# it clones Homebrew/brew from a flake input into the prefix, so brew's own
# version is pinned in flake.lock and moves on `nix flake update`. nix-darwin's
# `homebrew` renders a Brewfile and runs `brew bundle` against it. Neither puts
# anything in the store, so none of it rolls back with a generation.
#
# Every cask here is flagged `auto_updates`, so brew's recorded version goes
# stale by design while the app moves itself.
#
# Requires `inputs.nix-homebrew.darwinModules.nix-homebrew` alongside it.
{ ... }:
{
  nix-homebrew = {
    enable = true;
    # No Intel prefix under /usr/local: nothing here needs Rosetta.
    enableRosetta = false;
    # No taps, enforced structurally: with none declared and this false,
    # nix-homebrew points $HOMEBREW_LIBRARY/Taps at an empty store path, so
    # `brew tap` cannot write rather than being asked not to. Every cask here
    # is default-tap, which brew resolves through its JSON API — that stays
    # on, because HOMEBREW_NO_INSTALL_FROM_API is set only when
    # homebrew/homebrew-core is declared. Also exports
    # HOMEBREW_NO_AUTO_UPDATE=1, which covers manual `brew install` the way
    # onActivation.autoUpdate only covers a switch (D16).
    mutableTaps = false;
  };

  homebrew = {
    enable = true;

    onActivation = {
      # A switch must not depend on what the tap says today: `brew update`
      # would let the same flake produce different software on two machines.
      autoUpdate = false;
      # Unwanted and also moot — `--upgrade` skips auto_updates casks (only
      # `--greedy` reaches them) and there are no formulae left for it to move.
      upgrade = false;
      # The drift detector we want, but not yet: "uninstall" removes every
      # brew package this file does not name, and the pre-nix Homebrew on
      # `work` is still full of them. Flip it after the Phase 5 purge (D16).
      cleanup = "none";
    };

    # Nothing from a third-party tap: Homebrew 6.0 requires those to be
    # trusted before it will load them (nix-homebrew's `trust.taps`), and the
    # appliance set has no reason to leave the default tap.
    casks = [
      "1password" # browser integration and system auth verify the real bundle
      "google-chrome"
      "karabiner-elements" # the official pqrs .pkg; nixpkgs' own is rejected in D16
    ];
  };
}
