# kube-fzf: fzf-driven pod finder for kubectl (findpod / tailpod / execpod /
# describepod / pfpod). Not in nixpkgs, so it is written here as an
# upstreamable package expression rather than a flake input (D14) — this file
# is `pkgs/by-name/ku/kube-fzf/package.nix` with the path changed.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  coreutils,
  fzf,
  gawk,
  kubectl,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "kube-fzf";
  version = "1.6.3";

  src = fetchFromGitHub {
    owner = "thecasualcoder";
    repo = "kube-fzf";
    tag = "v${finalAttrs.version}";
    hash = "sha256-WstAAUTmA97K6/1LshRUKcZGxvvBM5mtZu2OuUsSi3A=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # Each command does `source kube-fzf.sh` unless KUBE_FZF_PATH is set — a
  # bare `source` searches PATH, which only works because upstream's installer
  # drops the library next to the commands in bin/. Setting KUBE_FZF_PATH
  # instead keeps the library out of bin/ and makes the lookup exact.
  installPhase = ''
    runHook preInstall

    install -Dm444 kube-fzf.sh -t $out/share/kube-fzf

    for cmd in describepod execpod findpod pfpod tailpod; do
      install -Dm555 $cmd -t $out/bin
      wrapProgram $out/bin/$cmd \
        --set KUBE_FZF_PATH $out/share/kube-fzf/kube-fzf.sh \
        --prefix PATH : ${
          lib.makeBinPath [
            coreutils
            fzf
            gawk
            kubectl
          ]
        }
    done

    runHook postInstall
  '';

  meta = {
    description = "Find, tail, exec into and port-forward Kubernetes pods with fzf";
    homepage = "https://github.com/thecasualcoder/kube-fzf";
    license = lib.licenses.mit;
    mainProgram = "findpod";
    platforms = lib.platforms.unix;
  };
})
