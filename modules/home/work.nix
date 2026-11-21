# Employer-coupled configuration: things that exist only because of the
# employer's platform choices, split out so a consumer of these modules can
# take everything else without them (D17).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # op:// references, `op run` resolves them into spacectl's
  # environment for the length of one command.
  spaceliftEnv = pkgs.writeText "spacelift-env" ''
    SPACELIFT_API_KEY_ENDPOINT=op://Employee/Spacelift/url
    SPACELIFT_API_KEY_ID=op://Employee/Spacelift/username
    SPACELIFT_API_KEY_SECRET=op://Employee/Spacelift/credential
  '';

  # Where the Mac reaches carman's memory service: a LoadBalancer on the dev
  # VM's cluster, which lima forwards to loopback (DEVVM.md, Ports).
  cmemUrl = "http://127.0.0.1:8377";
  # The laptop role's token, as its login-keychain item (D35).
  cmemTokenItem = "cmem-laptop-token";
  # The memory's hooks for Claude Code, as a file for `claude --settings`:
  # they call cmem by its store path and carry no secret. Claude Code's own
  # memory is switched off in the same file, so a session has one memory;
  # its files stay under ~/.claude/projects and come back with `false`.
  cmemSettings = pkgs.carman.cmem-claude-code-settings.override {
    url = cmemUrl;
    disableAutoMemory = true;
    # Added to what a session is told when it starts without memory. The
    # service is on the dev VM, so the VM's own check is the place to look.
    unreachableHint = "Run `devvm-doctor` to see what is wrong with the dev VM that serves it, and the cure.";
  };

  # The agent pod's tmux, attached from this terminal (D38). carman's deploy
  # script, from its checkout, knows the pod and how to attach.
  desk = pkgs.writeShellApplication {
    name = "desk";
    runtimeInputs = [ pkgs.kubectl ];
    text = ''
      exec ${lib.escapeShellArg "${config.home.homeDirectory}/code/tmp/carman/scripts/deploy.sh"} devvm agent attach desk
    '';
  };
  # What the `desk` session runs: the attach, again whenever it ends, so the
  # session outlives a pod or VM restart. 0 means the pod's client was
  # detached there; anything else means the pod is unreachable.
  deskLoop = pkgs.writeShellScript "desk-loop" ''
    while true; do
      if ! ${lib.getExe desk}; then
        echo "desk: the agent pod is not reachable; trying again in 5 seconds"
        sleep 4
      fi
      sleep 1
    done
  '';
  # Inside `desk`, prefix + these act on this Mac's tmux, as in any other
  # session: choosing, switching and leaving sessions, and g, the reading
  # split of the Mac's clipboard (tmux.nix), where the pod's copies land.
  # Every other prefixed key is the pod's.
  deskLocalKeys = {
    g = "split-window -h -l 59 'pbpaste | glo'";
    "(" = "switch-client -p";
    ")" = "switch-client -n";
    w = "choose-tree -Zw";
    B = "switch-client -l";
    d = "detach-client";
    D = "choose-client -Z";
    C-z = "suspend-client";
  };
  deskForwardedKeys = lib.subtractLists (lib.attrNames deskLocalKeys) (
    lib.stringToCharacters "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789`~!@#$%^&*()-_=+[]{}\\|;:'\",.<>/?"
    ++ map (c: "C-${c}") (lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz")
    ++ [
      "C-Space"
      "Space"
      "Enter"
      "Escape"
      "Tab"
      "BSpace"
      "Up"
      "Down"
      "Left"
      "Right"
      "PageUp"
      "PageDown"
      "Home"
      "End"
    ]
  );
  # A key as one tmux config token.
  tmuxKey = key: if key == "'" then "\"'\"" else "'${key}'";

  # Keychain copies of 1Password items, service name to reference (D35):
  # tokens that sessions and unattended runs read without a prompt.
  keychainCopies = {
    # Inference only (`claude setup-token`), for test runs. Not for sessions.
    claude-test-token = "op://Private/Sparelabs Claude API Key/credential";
    ${cmemTokenItem} = "op://Private/carman cmem/laptop";
  };
  readKeychain =
    service: ''/usr/bin/security find-generic-password -s ${service} -a "$USER" -w 2>/dev/null'';
  # Refreshes the copies from 1Password; run by hand, one approval.
  keychainSync = pkgs.writeShellApplication {
    name = "keychain-sync";
    runtimeInputs = [ pkgs._1password-cli ];
    text = ''
      copy() {
        local value
        value=$(op read "$2") || return
        case $value in
          *[\"\\]* | *$'\n'*) echo "keychain: $1 has a character this cannot quote" >&2; return 1 ;;
        esac
        # On standard input, so the value is on no command line.
        printf 'add-generic-password -U -s %s -a %s -w "%s"\n' "$1" "$USER" "$value" |
          /usr/bin/security -i
        echo "keychain: $1 updated"
      }
      status=0
      ${lib.concatStrings (
        lib.mapAttrsToList (service: ref: ''
          copy ${lib.escapeShellArg service} ${lib.escapeShellArg ref} || status=1
        '') keychainCopies
      )}
      exit "$status"
    '';
  };
in
{
  home.packages = with pkgs; [
    # `op`. Unfree, so it needs the name allowlisted in the
    # `allowUnfreePredicate` in modules/darwin/work.nix before this module evaluates
    # (D18).
    _1password-cli
    spacectl # Spacelift CLI; the API credentials stay outside the repo
    spicedb # run the permissions database locally for development
    # carman's memory client (D33), from the overlay in
    # modules/darwin/work.nix. On PATH because an agent runs `cmem note` and
    # `cmem recall` by name; the hooks do not need it there.
    carman.cmem
    keychainSync
    desk
  ];

  # The pod's tmux as `desk`, a session of this server made at its start
  # (D38): tmux ls lists it and tmux attach -t desk enters it. Its own
  # status and prefix are off, so the bar is the pod's; C-Space there opens
  # deskprefix, where the session keys act here and the rest go to the pod
  # as prefix+key. set-clipboard on passes the pod's copies out.
  programs.tmux.extraConfig = lib.mkAfter ''
    set -g set-clipboard on
    bind -T desk C-Space switch-client -T deskprefix
    ${lib.concatStrings (
      lib.mapAttrsToList (key: command: ''
        bind -T deskprefix ${tmuxKey key} ${command}
      '') deskLocalKeys
    )}
    ${lib.concatMapStrings (key: ''
      bind -T deskprefix ${tmuxKey key} send-keys C-Space ${tmuxKey key}
    '') deskForwardedKeys}
    new-session -d -s desk ${deskLoop}
    set -t desk status off
    set -t desk prefix None
    set -t desk prefix2 None
    set -t desk key-table desk
  '';

  # 1Password is this machine's ssh agent. Two things about the line itself:
  # it is `Host *` because a machine has one agent, and the value is quoted
  # inside the Nix string because the path contains a space and home-manage
  # renders directives verbatim — unquoted, ssh rejects the whole config file.
  #
  # Harmless before the agent is switched on in the app: a socket that is not
  # there is a warning, and ssh falls through to the on-disk keys.
  programs.ssh.settings."*".IdentityAgent =
    ''"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'';

  # Bookmarked hosts, generated by 1Password from a URL field on each key item:
  # one `Match Host … User …` block per bookmark, pinning IdentityFile to that
  # key's public half under IdentitiesOnly.
  programs.ssh.includes = [ "~/.ssh/1Password/config" ];

  programs.bash.shellAliases.spacectl = "op run --env-file=${spaceliftEnv} -- ${pkgs.spacectl}/bin/spacectl";

  # `claude` is a function so that claude stays the foreground process and
  # tmux names the window after it. `env` because the native installer owns
  # the binary (D13); mkBefore keeps the ~/.bashrc.local hook last.
  #
  # It gives a session carman's memory (D33): hooks through `--settings`,
  # the token from the keychain (D35). No token, and the hook says so.
  #
  # git and gh are told not to prompt: nobody is at a session's terminal.
  #
  # `cmem` at a prompt reads the same token. One already in the environment
  # wins, which is how a trial service is aimed at.
  programs.bash.initExtra = lib.mkBefore ''
    claude() {
      local cmem_token
      cmem_token=$(${readKeychain cmemTokenItem})
      CMEM_TOKEN=$cmem_token env GIT_TERMINAL_PROMPT=0 GH_PROMPT_DISABLED=1 \
        claude --settings ${cmemSettings} "$@"
    }

    cmem() {
      local token=$CMEM_TOKEN
      if [ -z "$token" ] && ! token=$(${readKeychain cmemTokenItem}); then
        echo "cmem: no token in the keychain; run keychain-sync" >&2
        return 1
      fi
      CMEM_URL=''${CMEM_URL:-${cmemUrl}} CMEM_TOKEN=$token command cmem "$@"
    }
  '';
}
