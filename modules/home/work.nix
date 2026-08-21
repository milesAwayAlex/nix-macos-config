# Employer-coupled configuration: things that exist only because of the
# employer's platform choices, split out so a consumer of these modules can
# take everything else without them (D17).
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # `op`. Unfree, so it needs the name allowlisted in the
    # `allowUnfreePredicate` in hosts/work.nix before this module evaluates
    # (D18).
    _1password-cli
    spacectl # Spacelift CLI; the API credentials stay outside the repo
    spicedb # run the permissions database locally for development
  ];

  # 1Password is this machine's ssh agent, so its private keys stay in the
  # vault and never reach disk (D19). Two things about the line itself: it is
  # `Host *` because a machine has one agent, and the value is quoted inside
  # the Nix string because the path contains a space and home-manager renders
  # directives verbatim — unquoted, ssh rejects the whole config file.
  #
  # Harmless before the agent is switched on in the app: a socket that is not
  # there is a warning, and ssh falls through to the on-disk keys.
  programs.ssh.settings."*".IdentityAgent =
    ''"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'';
}
