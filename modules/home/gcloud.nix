# gcloud from nixpkgs. The trade: `gcloud components install/update` cannot
# work against a read-only store, so components are declared here instead.
#
# Auth state lives in ~/.config/gcloud and is untouched by where the binary
# comes from.
{ pkgs, ... }:
let
  gcloud = pkgs.google-cloud-sdk.withExtraComponents (
    with pkgs.google-cloud-sdk.components;
    [
      gke-gcloud-auth-plugin # kubectl's exec-auth plugin for GKE; not in the base package
    ]
  );
in
{
  home.packages = [ gcloud ];
}
