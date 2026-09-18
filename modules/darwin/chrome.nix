# Chrome policy, the part both machines share. The attribute name is handed to
# `defaults write` verbatim by an activation script running as root, so it has
# to be the full path — a bare `com.google.Chrome` would land in root's own
# preferences and do nothing.
#
# The password manager's extension is per host (D19): each hosts/<name>.nix
# adds `ExtensionInstallForcelist` to this same domain, and the two definitions
# merge — a clash on one key would fail the eval rather than pick a side.
{ ... }:
{
  system.defaults.CustomSystemPreferences."/Library/Preferences/com.google.Chrome" = {
    # Chrome ships its own resolver and would otherwise read the system's
    # servers but bypass getaddrinfo. There is no policy for naming a
    # plain-DNS server, only DoH, so this is how it is held to the machine's.
    BuiltInDnsClientEnabled = false;

    # The host's manager holds passwords (D19), so Chrome's own is off
    PasswordManagerEnabled = false;
    AutofillAddressEnabled = false;
    AutofillCreditCardEnabled = false;
    DefaultBrowserSettingEnabled = false;
  };
}
