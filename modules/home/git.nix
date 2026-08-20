# Git config. Note that ~/.gitconfig itself stays unmanaged and is
# surrendered to machine-local/IT-pushed entries (D9) — git reads it after
# this file, so its keys deliberately win.
{ ... }:
{
  programs.git = {
    enable = true;

    # Adopted from ~/.config/git/ignore (written there by Claude Code
    # 2025-07-24): keeps per-machine permission files out of every repo.
    ignores = [ "**/.claude/settings.local.json" ];

    includes = [
      {
        # Recognize this repo by remote URL (git 2.36+): robust to clone
        # path/name, shared by linked worktrees, portable across machines.
        # Retires D7's manual per-clone `git config core.hooksPath`.
        condition = "hasconfig:remote.*.url:git@github.com:milesAwayAlex/nix-macos-config.git";
        contents.core.hooksPath = ".githooks";
      }
    ];

    settings = {
      user = {
        name = "Alex Miles";
        email = "milesAwayAlex@gmail.com";
      };
      init.defaultBranch = "main"; # preference; work repos are cloned, not init'ed
      pull.ff = "only"; # non-ff pull errors out; rebase/merge is then explicit
      merge.conflictstyle = "zdiff3";
      diff.algorithm = "histogram";
      push.autoSetupRemote = true;
      worktree.guessRemote = true;

      # Perf, kept from the old config (verified non-default on 2.54):
      core.untrackedCache = true; # default "keep"; APFS mtimes are reliable
      checkout.workers = 0; # default 1 (sequential); 0 = all logical cores
      fetch.writeCommitGraph = true; # default false; incremental graph per fetch
      pack.threads = 0; # explicit auto (docs don't state the unset default)
    };
  };
}
