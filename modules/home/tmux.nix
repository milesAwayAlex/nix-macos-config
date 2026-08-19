# tmux, ported 2026-08-18 from ~/configs/tmux/.tmux.conf after review against
# the 3.6a man page. Hand-rolled, no plugins. Deltas from the legacy file:
# default-terminal xterm-256color -> tmux-256color (the man requires a
# screen/tmux derivative; macOS ships the entry in /usr/share/terminfo),
# truecolor advertised for the alacritty outer (its terminfo lacks RGB, and
# the old ",xterm*:RGB" pattern never matched it), focus-events on (for
# editor autoread later), and redundant-with-default lines dropped
# (set-titles off, automatic-rename on, visual-activity off).
{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    keyMode = "vi"; # covers both mode-keys and status-keys
    escapeTime = 50;
    prefix = "C-Space";
    terminal = "tmux-256color";
    # Panes spawn this as login shells
    # (tmux's empty default-command semantics)
    shell = "${pkgs.bashInteractive}/bin/bash";
    focusEvents = true;
    extraConfig = ''
      # Truecolor through the alacritty outer (its terminfo has no RGB cap).
      set -as terminal-features ",alacritty:RGB"

      # macOS path_helper demotes nix dirs in login panes, and the inherited
      # guard makes nix-darwin's set-environment skip the rebuild — so
      # /usr/bin/git shadows nix git. Strip the guard: each pane re-runs
      # set-environment and gets the canonical nix-first PATH.
      set-environment -gr __NIX_DARWIN_SET_ENVIRONMENT_DONE

      set -g renumber-windows on
      set -g monitor-activity on
      set -g activity-action none
      set -g bell-action none

      # Minimal status: centered window list, transparent bar, clock only.
      set -g status-justify centre
      set -g status-style bg=default,fg=brightblack
      set -g status-right "%H:%M"
      # Prefix armed → asterisk beside the session tab.
      set -g status-left "[#S] #{?client_prefix,* ,}"
      set -g pane-border-style fg=black
      set -g pane-active-border-style fg=brightgreen
      set -g window-status-activity-style fg=brightyellow
      set -g window-status-current-style fg=brightgreen

      # A server started from inside another tmux gets a distinct status bar.
      %if #{TMUX}
      set -g status-style bg=black,fg=brightblue
      %endif

      # Splits/windows: lowercase inherits the pane's cwd, uppercase uses the
      # session's start directory.
      bind v split-window -vc '#{pane_current_path}'
      bind s split-window -hc '#{pane_current_path}'
      bind c new-window -ac '#{pane_current_path}'
      bind V split-window -v
      bind S split-window -h
      bind C new-window
      bind B switch-client -l
      bind b last-window
      bind Q display-panes
      bind q set status
      bind N next-window -a
      bind P previous-window -a
      bind T swap-window -t 0

      # Render clipboard markdown in an 80-column split (glow's layout
      # assumes ~80), darwin-only.
      bind g split-window -h -l 80 'pbpaste | ${pkgs.glow}/bin/glow -p -'

      # Whole scrollback → macOS clipboard (sharing, feeding to Claude).
      bind y { run-shell 'tmux capture-pane -p -S - | pbcopy'; display-message "scrollback copied" }

      # Copy-mode: vi select/yank; y stays in copy mode (deliberate, plain
      # copy-selection). set-clipboard's default (external) plus alacritty's
      # Ms terminfo capability put yanks on the macOS clipboard via OSC 52.
      bind -T copy-mode-vi v send -X begin-selection
      bind -T copy-mode-vi y send -X copy-selection

      # Pane navigation and resize
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R
      bind -r H { resize-pane -L; display-message "#{pane_width}x#{pane_height}" }
      bind -r J { resize-pane -D; display-message "#{pane_width}x#{pane_height}" }
      bind -r K { resize-pane -U; display-message "#{pane_width}x#{pane_height}" }
      bind -r L { resize-pane -R; display-message "#{pane_width}x#{pane_height}" }
    '';
  };
}
