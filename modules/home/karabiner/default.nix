# Karabiner-Elements config. Karabiner can't take its config via symlink —
# the watcher misses edits made through the link, and GUI edits replace the
# link with a plain file (both confirmed by live test) — so converge a real
# writable file instead. The repo copy is canonical: drift
# in the live file is overwritten on every switch.
# Convention: comparison tools are store-pinned (diffutils); POSIX-universal
# basics ride the activation PATH bare.
{ lib, pkgs, ... }:
{
  home.activation.karabinerConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    karabinerSrc=${./karabiner.json}
    karabinerDst="$HOME/.config/karabiner/karabiner.json"
    if ! ${pkgs.diffutils}/bin/cmp -s "$karabinerSrc" "$karabinerDst"; then
      if [ -f "$karabinerDst" ]; then
        echo "karabiner.json: live file differs from declared state; overwriting"
      fi
      run mkdir -p "$HOME/.config/karabiner"
      run install -m 644 "$karabinerSrc" "$karabinerDst"
    fi
  '';
}
