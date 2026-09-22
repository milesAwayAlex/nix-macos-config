# ~/Library/Preferences/glow/glow.yml. On macOS glow reads it regardless of
# XDG_CONFIG_HOME, so home.file targets it directly instead of xdg.configFile.
# Consequence of HM ownership: `glow config` can no longer edit it in place.
{ pkgs, ... }:
let
  # glow for prose some tool hard-wrapped at 80: deno fmt joins the
  # paragraphs first (D26) — code, lists and tables it leaves alone — then
  # glo-tables.ts turns tables the terminal cannot hold into one block per
  # row, then glow renders at the terminal's own width. Reads the files
  # given, else stdin.
  glo = pkgs.writeShellApplication {
    name = "glo";
    runtimeInputs = [
      pkgs.deno
      pkgs.glow
    ];
    text = ''
      cat -- "$@" | deno fmt --ext md --prose-wrap never - \
        | deno run ${./glo-tables.ts} | glow -
    '';
  };
in
{
  home.packages = [
    pkgs.glow
    glo
  ];

  home.file."Library/Preferences/glow/glow.yml".text = ''
    # style name or JSON path (default "auto"); vim uses the same one
    style: "dracula"
    # mouse support (TUI-mode only)
    mouse: false
    # use pager to display markdown
    pager: true
    # word-wrap at width. 0: the terminal's own width (glow caps it at
    # 120), 80 when piped. The tmux `prefix g` split counts on it.
    width: 0
    # show all files, including hidden and ignored
    all: false
  '';
}
