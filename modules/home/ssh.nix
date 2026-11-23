{ ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    # Git reaches GitHub over HTTPS (D34), so ssh to github.com is only ever a
    # probe; without an agent it fails at once instead of asking for the key.
    settings."github.com".IdentityAgent = "none";
  };
}
