# Kubernetes toolchain, kubectl 1.36
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    kubectl
    kubectx
    kubernetes-helm
    k9s
    argocd
    argo-rollouts
    kind
    (callPackage ../../packages/kube-fzf.nix { }) # not in nixpkgs (D14)
  ];
}
