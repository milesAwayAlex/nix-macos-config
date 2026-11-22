# Alex's shell for the agent pod on the dev VM's cluster (D38): the portable
# home modules, built for Linux, with nothing tied to macOS, a keychain, an
# account or a secret. packages/agent-home.nix wraps it for the image.
{ lib, pkgs, ... }:
{
  imports = [
    ./bash
    ./git.nix
    ./gnu.nix
    ./pkgs.nix
    ./tmux.nix
    ./vim
  ];

  # The pod's user. Its home is a volume, so these files reach it at the
  # pod's start, through agent-home-link.
  home.username = "agent";
  home.homeDirectory = "/home/agent";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    kubernetes-helm # the work hosts' helm (k8s.nix), for charts' checks
    less # git's pager; the slim image has none
    ncurses # terminfo for tmux-256color and the Mac's alacritty
    tzdata
  ];

  # Debian's /etc/profile resets PATH in every login shell, tmux's panes
  # among them; .bashrc puts the profile back in front.
  programs.bash.initExtra = lib.mkBefore ''
    PATH="$HOME/.nix-profile/bin:$PATH"
  '';

  # The empty last entry keeps the image's own terminfo directories.
  home.sessionVariables = {
    TERMINFO_DIRS = "${pkgs.ncurses}/share/terminfo:";
    TZDIR = "${pkgs.tzdata}/share/zoneinfo";
  };

  # Inside the Mac's `desk` session (modules/home/work.nix) the terminal is
  # that tmux, which passes true colour and the clipboard through. Programs
  # here may set the Mac's clipboard too, as /copy does (Alex's call, D38).
  # The bar names the pod.
  programs.tmux.extraConfig = lib.mkAfter ''
    set -as terminal-features ",tmux*:RGB:clipboard"
    set -g set-clipboard on
    set -g status-left-length 40
    set -g status-left "#[fg=brightmagenta]#h#[default] [#S] #{?client_prefix,* ,}"
  '';

  # One locale, not glibc's 220 MiB of them; C.UTF-8 is built into glibc.
  i18n.glibcLocales = pkgs.glibcLocales.override {
    allLocales = false;
    locales = [ "en_US.UTF-8/UTF-8" ];
  };

  # Commits from the pod carry whatever identity the pod is given.
  programs.git.settings.user = lib.mkForce { };
}
