# Alacritty, ported 2026-08-18 from the pre-0.13 ~/.alacritty.yml after a
# line-by-line review against the 0.17 man pages (alacritty.5,
# alacritty-bindings.5). Philosophy: fullscreen dumb terminal — tmux owns
# scrollback, search, and copy-mode, so the bindings only unbind the mode
# entry points;
{ lib, pkgs, ... }:
{
  programs.alacritty = {
    enable = true;
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
      };

      colors = {
        draw_bold_text_with_bright_colors = true;
        primary = {
          background = "#0d0c13";
          foreground = "#ffbdec";
        };
        cursor = {
          text = "#ff271d";
          cursor = "#ffbdec";
        };
        normal = {
          black = "#2d2e29";
          red = "#ff5458";
          green = "#0f995b";
          yellow = "#fede5d";
          blue = "#4b5072";
          magenta = "#b267e6";
          cyan = "#63f2f1";
          white = "#d6b3cc";
        };
        bright = {
          black = "#565575";
          red = "#ff8080";
          green = "#72f1b8";
          yellow = "#ffe9aa";
          blue = "#848bbd";
          magenta = "#ff7edb";
          cyan = "#aaffe4";
          white = "#ebe3e7";
        };
      };

      # Non-login interactive bash, matching pre-port behavior. The login
      # shell is still /bin/zsh until the Phase 4 bash slice flips it — this
      # line is what puts bash in the terminal meanwhile.
      terminal.shell.program = "${pkgs.bashInteractive}/bin/bash";

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
