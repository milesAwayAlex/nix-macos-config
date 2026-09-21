# Alacritty, fullscreen dumb terminal. tmux owns scrollback, search,
# and copy-mode, so the bindings only unbind the mode entry points
{ lib, pkgs, ... }:
{
  programs.alacritty = {
    enable = true;

    # Primer's accessibility palette, every ANSI slot at 9:1 or better on its
    # near-black background; imported from nixpkgs' alacritty-theme, so no
    # colour values live here. It feeds everything that speaks ANSI — prompt,
    # ls, tmux, git. Vim and glow bring their own Dracula and only need not to
    # clash with the background they inherit.
    theme = "github_dark_high_contrast";

    settings = {
      window = {
        dynamic_padding = true;
        startup_mode = "Fullscreen";
        dynamic_title = false;
      };

      scrolling.history = 0; # tmux owns scrollback

      font = {
        normal.family = "Hack";
        size = lib.mkDefault 23.0; # host-tunable
        # 1.3x line spacing reads easier than the font's own. Alacritty has
        # no multiplier, only whole physical pixels added to the cell: Hack's
        # line is 54 px at 23 pt on a 2x display, so 16 makes it 70. Glyphs
        # sit at the cell's bottom; half the extra lifts them back to the
        # middle.
        offset.y = 16;
        glyph_offset.y = 8;
      };

      # Login bash macOS GUI apps inherit launchd's empty env, so each window
      # bootstraps a full session via /etc/profile, macOS-terminal style.
      terminal.shell = {
        program = "${pkgs.bashInteractive}/bin/bash";
        args = [ "--login" ];
      };

      mouse.hide_when_typing = true;

      hints.enabled = [
        {
          # Click copies the URL (deliberate; the stock default opens it).
          regex = "(ipfs:|ipns:|magnet:|mailto:|gemini:|gopher:|https:|http:|news:|file:|git:|ssh:|ftp:)[^\\u0000-\\u001F\\u007F-\\u009F<>\"\\\\s{-}\\\\^⟨⟩`]+";
          action = "Copy";
          post_processing = true;
          mouse.enabled = true;
        }
      ];

      keyboard.bindings = [
        # Vi-mode entry point — killed (tmux copy-mode instead).
        {
          key = "Space";
          mods = "Control|Shift";
          mode = "~Search";
          action = "ReceiveChar";
        }
        # Search entry points — killed (tmux search instead).
        {
          key = "F";
          mods = "Command";
          mode = "~Search";
          action = "None";
        }
        {
          key = "B";
          mods = "Command";
          mode = "~Search";
          action = "None";
        }
        # No tabs.
        {
          key = "T";
          mods = "Command";
          action = "None";
        }
        # No clear-screen surprise.
        {
          key = "K";
          mods = "Command";
          mode = "~Vi|~Search";
          action = "None";
        }
        # No Hide / HideOtherApplications.
        {
          key = "H";
          mods = "Command";
          action = "None";
        }
        {
          key = "H";
          mods = "Command|Alt";
          action = "None";
        }
        # Programmer Dvorak: digits need shift, so Cmd+0 (ResetFontSize) is
        # awkward — Cmd+R instead. Increase/decrease need no rebinding: 0.17
        # matches produced characters, so Cmd+'+' (physical 9) and Cmd+'='
        # (physical 6) hit IncreaseFontSize natively.
        {
          key = "R";
          mods = "Command";
          action = "ResetFontSize";
        }
      ];
    };
  };
}
