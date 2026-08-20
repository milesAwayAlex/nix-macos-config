# gh's config only — the module brings the package. Auth stays in
# ~/.config/gh/hosts.yml, which HM deliberately does not manage.
{ ... }:
{
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh"; # gh's own default is https
    };
  };
}
