# Alex's shell as one tree for the agent pod's image (D38): `profile` is
# home-manager's package set, `home` its dotfiles. The pod's home is a
# volume, so agent-home-link puts both in place each time the pod starts.
{
  home,
  coreutils,
  findutils,
  runCommand,
  writeShellApplication,
}:
let
  inherit (home.config) home-files;
  profile = home.config.home.path;

  link = writeShellApplication {
    name = "agent-home-link";
    runtimeInputs = [
      coreutils
      findutils
    ];
    text = ''
      state="$HOME/.local/state/agent-home"
      mkdir -p "$state"
      # Where home-manager's .profile looks for its session variables.
      ln -sfn ${profile} "$HOME/.nix-profile"

      # Each generated file, linked at its path under $HOME. A real file in
      # the way is kept beside it.
      find ${home-files} -type l -printf '%P\n' | sort >"$state/links.new"
      while IFS= read -r path; do
        target="$HOME/$path"
        mkdir -p "$(dirname "$target")"
        if [ -e "$target" ] && [ ! -L "$target" ]; then
          mv "$target" "$target.before-agent-home"
        fi
        ln -sfn "${home-files}/$path" "$target"
      done <"$state/links.new"

      # Links an earlier image made that this one no longer does.
      if [ -f "$state/links" ]; then
        comm -23 "$state/links" "$state/links.new" | while IFS= read -r path; do
          if [ -L "$HOME/$path" ]; then rm "$HOME/$path"; fi
        done
      fi
      mv "$state/links.new" "$state/links"
    '';
  };
in
runCommand "agent-home" { } ''
  mkdir -p $out/bin
  ln -s ${profile} $out/profile
  ln -s ${home-files} $out/home
  ln -s ${link}/bin/agent-home-link $out/bin/agent-home-link
''
