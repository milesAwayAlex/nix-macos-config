# Touch ID for sudo. The two lines below are the whole of
# /etc/pam.d/sudo_local, a file nix-darwin already owns and macOS 14+ already
# includes from /etc/pam.d/sudo — so nothing here rewrites an auth path by
# hand.
#
# Safe by construction, which is what makes it worth doing at all: pam_tid is
# `sufficient`, so a failure falls through to pam_opendirectory and the
# password prompt, and pam_reattach is `optional`, so a module that will not
# load is skipped. No state of these two can lock sudo out. pam_tid.so is
# named bare because it is Apple's, from the system PAM path, not a store path
# that could go stale under the running system.
#
# Inert until a fingerprint is enrolled, which is manual and per-user
# (BOOTSTRAP.md); until then sudo behaves exactly as it did before.
{ ... }:
{
  security.pam.services.sudo_local = {
    # tmux's server outlives the login session and is reattached to a
    # different bootstrap session, so PAM cannot present it the Touch ID
    # prompt and sudo drops silently back to the password — which would be
    # nearly every sudo on this machine. nix-darwin emits this line ahead of
    # pam_tid, which is the order that works.
    reattach = true;
    touchIdAuth = true;
  };
}
