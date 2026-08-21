# macOS preferences, written as `defaults write` at activation and never read
# back. Two consequences worth knowing before adding to this file: deleting a
# key here stops it being written but does not restore the previous value, and
# anything MDM pushes into /Library/Managed Preferences outranks everything
# below. nix-darwin also does not kick the affected app, so Dock and Finder
# changes need a `killall Dock` or a logout to show up.
{ ... }:
{
  system.defaults.NSGlobalDomain = {
    # Faster than the Keyboard pane can express: the unit is a 15 ms tick, and
    # the sliders bottom out at 2 (30 ms) and 15 (225 ms).
    KeyRepeat = 1;
    InitialKeyRepeat = 10;

    # Holding a key repeats it instead of opening the accent picker — the
    # thing that makes vim's hjkl usable outside a terminal.
    ApplePressAndHoldEnabled = false;
  };

  system.defaults.dock = {
    autohide = true;

    # Every corner disabled (1). Only the bottom right was ever assigned — to
    # Quick Note, which fires on any stray throw of the cursor down there —
    # but naming all four means neither System Settings nor a macOS upgrade
    # can quietly hand one of them back out.
    wvous-tl-corner = 1;
    wvous-tr-corner = 1;
    wvous-bl-corner = 1;
    wvous-br-corner = 1;
  };
}
