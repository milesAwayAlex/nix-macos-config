# Input layer: Programmer Dvorak at the system level (login window included)
# and Karabiner's pre-login (system default) configuration. Both are plain
# root file copies, automating exactly what the vendor installers/GUIs do.
#
# programmer-dvorak.bundle: Roland Kaufmann's official macOS distribution,
# vendored verbatim from ProgrammerDvorak-1_2_13.pkg.zip (sha256
# 842ffaf714aaac91b0287c4e4576f18be1bfc32693709593a118572a7cc78006, the
# Homebrew-cask-pinned artifact) and verified byte-identical to the bundle
# already installed on `work`. https://www.kaufmann.no/roland/dvorak/
{ pkgs, ... }:
{
  # Show the input menu at the login window so the layout is selectable there.
  system.defaults.CustomSystemPreferences."com.apple.loginwindow".showInputMenu = true;

  # Convention: comparison tools are store-pinned (diffutils, locked by the
  # flake); POSIX-universal basics (mkdir/cp/rm/install) ride the activation
  # PATH bare.
  system.activationScripts.postActivation.text = ''
    layoutDst="/Library/Keyboard Layouts/Programmer Dvorak.bundle"
    if ! ${pkgs.diffutils}/bin/diff -rq ${./programmer-dvorak.bundle} "$layoutDst" >/dev/null 2>&1; then
      echo "installing Programmer Dvorak.bundle"
      rm -rf "$layoutDst"
      cp -R ${./programmer-dvorak.bundle} "$layoutDst"
    fi

    # Karabiner "use before login" config: the same file the home module
    # converges for the session, kept in lockstep at the system path.
    kbDst="/Library/Application Support/org.pqrs/config/karabiner.json"
    if ! ${pkgs.diffutils}/bin/cmp -s ${../../home/karabiner/karabiner.json} "$kbDst"; then
      echo "updating Karabiner system (pre-login) configuration"
      mkdir -p "$(dirname "$kbDst")"
      install -m 644 ${../../home/karabiner/karabiner.json} "$kbDst"
    fi
  '';
}
