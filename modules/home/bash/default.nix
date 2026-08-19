{ ... }:
{
  programs.bash = {
    enable = true;

    historySize = 100000;
    historyFileSize = 100000;
    historyControl = [
      "ignoredups"
      "ignorespace"
    ];
    historyIgnore = [
      "&"
      "ls"
      "ls *"
      "[bf]g"
      "f"
      "vim"
      "cd *"
      "exit"
    ];

    shellOptions = [
      "checkwinsize"
      "histappend"
      "cmdhist"
      "dotglob"
      "autocd"
    ];

    shellAliases = {
      ls = "ls -G";
      l = "ls -CF";
      ll = "ls -ahlF";
      la = "ls -A";
      grep = "grep --color";
      f = "fg";
      one = "git log --oneline --all --graph";
    };

    initExtra = ''
      set -o noclobber
      set -o vi

      export EDITOR=vim
      export NX_DAEMON=false
      export CLAUDE_CODE_NO_FLICKER=1

      # Own bins outrank everything; brew is appended so nix stays ahead.
      PATH="$HOME/bin:$HOME/.local/bin:$PATH"
      [ -d /opt/homebrew/bin ] && PATH="$PATH:/opt/homebrew/bin"
      export PATH

      . ${./prompt.bash}

      # Machine-local hook (D10), deliberately last: IT/EDR cert exports and
      # parked per-machine tooling (nvm, gcloud, deno, ...) live there.
      [ -r "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"
    '';
  };

  # ~/.inputrc — readline-wide, so vi editing applies to psql etc. too.
  programs.readline = {
    enable = true;
    variables = {
      editing-mode = "vi";
      keymap = "vi";
      visible-stats = true;
      mark-symlinked-directories = true;
      colored-stats = true;
      skip-completed-text = true;
    };
  };
}
