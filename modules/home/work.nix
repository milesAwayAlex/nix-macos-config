# Tools that only exist because of the employer's platform choices, split out
# so a consumer of these modules can take everything else without them (D17).
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # `op`. Unfree, so it needs the name allowlisted in
    # modules/darwin/unfree.nix before this module will evaluate (D18).
    _1password-cli
    spacectl # Spacelift CLI; the API credentials stay outside the repo
    spicedb # run the permissions database locally for development
  ];
}
