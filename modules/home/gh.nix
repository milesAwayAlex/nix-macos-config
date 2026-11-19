# gh's config, and GitHub's git through gh's login (D34). Auth stays in
# ~/.config/gh/hosts.yml, which HM deliberately does not manage.
{ ... }:
{
  programs.gh = {
    enable = true;
    settings = {
      # The remote gh writes into a new clone. `gh auth login` records its
      # own answer per host in hosts.yml, and that one wins (BOOTSTRAP.md).
      git_protocol = "https";
    };
  };

  # GitHub's ssh-form URLs are dialed over HTTPS, where git asks gh — the
  # module above makes it github.com's credential helper — and nothing
  # prompts. Covers what gh did not clone: existing remotes, pasted commands.
  programs.git.settings.url."https://github.com/".insteadOf = [
    "git@github.com:"
    "ssh://git@github.com/"
  ];
}
