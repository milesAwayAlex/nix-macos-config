# Personal-machine configuration: what exists because Bitwarden is this
# machine's password manager, split out the way work.nix is for the employer's
# (D17, D19).
{ ... }:
{
  # Bitwarden's desktop app is this machine's ssh agent. `Host *` because a
  # machine has one agent (D19). The path is the direct-download build's; the
  # App Store build keeps its socket inside its sandbox container.
  #
  # Harmless before the agent is switched on in the app: a socket that is not
  # there is a warning, and ssh falls through to the on-disk keys.
  programs.ssh.settings."*".IdentityAgent = "~/.bitwarden-ssh-agent.sock";
}
