# ~/Library/Preferences/glow/glow.yml. On macOS glow reads it regardless of
# XDG_CONFIG_HOME, so home.file targets it directly instead of xdg.configFile.
# Consequence of HM ownership: `glow config` can no longer edit it in place.
{ pkgs, ... }:
{
  home.packages = [ pkgs.glow ];

  home.file."Library/Preferences/glow/glow.yml".text = ''
    # style name or JSON path (default "auto"); vim uses the same one
    style: "dracula"
    # mouse support (TUI-mode only)
    mouse: false
    # use pager to display markdown
    pager: true
    # word-wrap at width — matches the tmux `prefix g` 80-column split
    width: 80
    # show all files, including hidden and ignored
    all: false
  '';
}
