# Chrome policy, the part every machine shares. The attribute name is handed to
# `defaults write` verbatim by an activation script running as root, so it has
# to be the full path — a bare `com.google.Chrome` would land in root's own
# preferences and do nothing.
#
# Chrome takes a plist written this way at its Recommended level, not
# Mandatory: macOS reports only managed preferences as forced. So these keys
# are defaults the user can flip in Settings, not locks, and a force-install
# list would be ignored outright — the password manager's extension is a hand
# install (D19, BOOTSTRAP.md).
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
