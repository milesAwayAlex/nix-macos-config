# Chrome policy. The attribute name is handed to `defaults write` verbatim by
# an activation script running as root, so it has to be the full path — a bare
# `com.google.Chrome` would land in root's own preferences and do nothing.
{ ... }:
{
  system.defaults.CustomSystemPreferences."/Library/Preferences/com.google.Chrome" = {
    # 1Password, force-installed so a fresh profile arrives with it. The
    # suffix is Chrome's own extension update service.
    ExtensionInstallForcelist = [
      "aeblfdkhhhdcdjpifhhbdiojplfjncoa;https://clients2.google.com/service/update2/crx"
    ];

    # 1Password is the password manager, so Chrome's own is off
    PasswordManagerEnabled = false;
    AutofillAddressEnabled = false;
    AutofillCreditCardEnabled = false;
    DefaultBrowserSettingEnabled = false;
  };
}
