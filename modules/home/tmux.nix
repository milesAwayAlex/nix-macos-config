# tmux, hand-rolled, no plugins. default-terminal must name a screen/tmux
# derivative per the man page, and macOS ships the tmux-256color entry in
# /usr/share/terminfo. Truecolor is advertised per-outer rather than by
# pattern because alacritty's terminfo lacks RGB. focus-events is on for
# editor autoread.
{ config, pkgs, ... }:
let
  view = pkgs.writeShellApplication {
    name = "tmux-view";
    runtimeInputs = [ pkgs.tmux ];
    text = ''
      if [ "$#" -gt 1 ]; then
        echo "usage: tmux-view [existing-session]" >&2
        exit 2
      fi
      if [ -n "''${TMUX:-}" ]; then
        echo "tmux-view: run from a plain shell in another terminal window" >&2
        exit 1
      fi
      if [ "$#" -eq 1 ]; then
        tmux has-session -t "=$1"
        session=$1
      else
        # Resolve the default before creating a session that could become it.
        tmux has-session
        session=$(tmux display-message -p '#{session_id}')
      fi
      view=$(tmux new-session -d -t "$session" -s "view-$$" -P -F '#{session_id}')
      # Also clean up if attachment fails. Only this helper's session is owned.
      trap 'tmux kill-session -t "$view" 2>/dev/null || true' EXIT
      # Arm cleanup after attaching: an unattached session would die at once.
      tmux attach-session -t "$view" \; set-option -t "$view" destroy-unattached on
    '';
  };

  scratchpad = pkgs.writeShellApplication {
    name = "tmux-scratchpad";
    runtimeInputs = [ pkgs.tmux ];
    text = ''
      # One editor per tmux server, even when called from another session.
      # The pane option disappears with the editor's pane.
      panes=$(tmux list-panes -a \
        -f '#{&&:#{@scratchpad},#{==:#{pane_dead},0}}' -F '#{pane_id}')
      # Grouped sessions list the same shared pane more than once.
      pane=''${panes%%$'\n'*}
      session=$2
      if [ -z "$pane" ]; then
        pane=$(tmux split-window -h -l 59 -t "$session:.$1" -c "$HOME" \
          -P -F '#{pane_id}' \
          ${config.programs.vim.package}/bin/vim "$HOME/.scratchpad.md")
        tmux set-option -p -t "$pane" @scratchpad 1
      fi
      window=$(tmux display-message -p -t "$pane" '#{window_id}')
      # Select through this session, preserving independent grouped views.
      # An unrelated session can share the window too, without a second Vim.
      if ! tmux select-window -t "$session:$window" 2>/dev/null; then
        tmux link-window -a -s "$window" -t "$session:"
      fi
      tmux select-pane -t "$pane"
    '';
  };
in
{
  home.packages = [ view ];

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

      # Render clipboard markdown in a reading split, darwin-only. glo
      # (glow.nix) unwraps the paragraphs and lets glow take the pane's
      # width, so 59 gives the 55 text columns a monospace line reads best
      # at, two columns of glow margin each side. Called by name: it sits in
      # the profile bin beside tmux itself, so wherever tmux resolved, glo
      # does too.
      bind g split-window -h -l 59 'pbpaste | glo'

      # Persistent Markdown scratchpad; Vim owns saving and explicit copying.
      # Session IDs contain '$'; single quotes protect them from the shell.
      bind e run-shell "${scratchpad}/bin/tmux-scratchpad '#{pane_id}' '#{session_id}'"

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
