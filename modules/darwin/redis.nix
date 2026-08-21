# Redis for local development, run as a launchd user agent with KeepAlive —
# the same always-on shape brew's service had.
#
# Two of nix-darwin's defaults are wrong for a laptop and fixed below: it
# binds every interface, and it writes `dir` into /etc/redis.conf without
# creating that directory, which redis treats as fatal.
{ config, ... }:
let
  user = config.system.primaryUser;
  dataDir = "${config.users.users.${user}.home}/.local/share/redis";
in
{
  services.redis = {
    enable = true;
    bind = "127.0.0.1";
    inherit dataDir;
  };

  # The agent runs as the primary user, so the default /var/lib/redis would be
  # unwritable even if it existed.
  system.activationScripts.postActivation.text = ''
    install -d -o ${user} -g staff -m 700 ${dataDir}
  '';
}
