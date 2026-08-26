# macOS preferences: one `defaults write` per key at activation, never read
# back. Removing a key stops it being written but leaves the last value on the
# machine, so a revert means setting the opposite value and switching — not
# deleting the line. Nothing here is enforced between switches; System Settings
# can change any of it freely.
#
# PREFERENCES.md is the operating manual: adding and removing keys, what needs
# a restart or a logout, crossing a nix-darwin version, and reading the drift
# the tool below reports.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.system.defaults;
  home = config.users.users.${config.system.primaryUser}.home;

  # Which domains `defaults` is handed for each option group, mirroring
  # nix-darwin's own defaults-write.nix. This restates upstream, so it can go
  # stale — a renamed group would quietly stop being checked, a moved domain
  # would report false drift. The assertion below compares it against the
  # `defaults write` lines nix-darwin actually emits, which turns either into a
  # failed build. `alf` is absent deliberately: its options were removed
  # upstream and throw when forced.
  targets = {
    ".GlobalPreferences" = [ ".GlobalPreferences" ];
    ActivityMonitor = [ "com.apple.ActivityMonitor" ];
    LaunchServices = [ "com.apple.LaunchServices" ];
    NSGlobalDomain = [ "-g" ];
    SoftwareUpdate = [ "/Library/Preferences/com.apple.SoftwareUpdate" ];
    WindowManager = [ "com.apple.WindowManager" ];
    controlcenter = [ "${home}/Library/Preferences/ByHost/com.apple.controlcenter" ];
    dock = [ "com.apple.dock" ];
    finder = [ "com.apple.finder" ];
    hitoolbox = [ "com.apple.HIToolbox" ];
    iCal = [ "com.apple.iCal" ];
    loginwindow = [ "/Library/Preferences/com.apple.loginwindow" ];
    menuExtraClock = [ "com.apple.menuextra.clock" ];
    screencapture = [ "com.apple.screencapture" ];
    screensaver = [ "com.apple.screensaver" ];
    smb = [ "/Library/Preferences/SystemConfiguration/com.apple.smb.server" ];
    spaces = [ "com.apple.spaces" ];
    universalaccess = [ "com.apple.universalaccess" ];
    # Written twice; a disagreement between the two is drift.
    magicmouse = [
      "com.apple.AppleMultitouchMouse"
      "com.apple.driver.AppleMultitouchMouse.mouse"
    ];
    trackpad = [
      "com.apple.AppleMultitouchTrackpad"
      "com.apple.driver.AppleBluetoothMultitouch.trackpad"
    ];
  };

  # A rename alias that traces a warning when forced; nix-darwin drops it from
  # its own writes for the same reason.
  aliases.dock = [ "expose-group-by-app" ];

  declared =
    domain:
    lib.filterAttrs (_: v: v != null) (
      builtins.removeAttrs (cfg.${domain} or { }) (aliases.${domain} or [ ])
    );

  isScalar = v: builtins.isBool v || builtins.isString v || builtins.isInt v || builtins.isFloat v;

  # toString mangles floats — 0.25 becomes 0.250000 — where toJSON matches what
  # `defaults read` prints back.
  wanted =
    v:
    if builtins.isBool v then
      (if v then "1" else "0")
    else if builtins.isString v then
      v
    else
      builtins.toJSON v;

  entry = label: domains: key: v: {
    inherit label domains key;
    scalar = isScalar v;
    want = if isScalar v then wanted v else "";
  };

  check =
    e:
    lib.concatStringsSep " " (
      [
        "check"
        (lib.escapeShellArg e.label)
        (lib.escapeShellArg e.key)
        (if e.scalar then "scalar" else "blob")
        (lib.escapeShellArg e.want)
      ]
      ++ map lib.escapeShellArg e.domains
    );

  typed = lib.concatLists (
    lib.mapAttrsToList (
      domain: domains: lib.mapAttrsToList (entry domain domains) (declared domain)
    ) targets
  );

  # Under these two the attribute name is the domain itself, which is why a
  # bare name lands in root's preferences rather than /Library's.
  custom =
    lib.concatMap
      (
        tree:
        lib.concatLists (
          lib.mapAttrsToList (
            domain: keys:
            lib.mapAttrsToList (entry "${tree} ${domain}" [ domain ]) (lib.filterAttrs (_: v: v != null) keys)
          ) (cfg.${tree} or { })
        )
      )
      [
        "CustomSystemPreferences"
        "CustomUserPreferences"
      ];

  entries = typed ++ custom;

  # The two sides of the assertion: every domain/key pair this module expects
  # to be written, and every one the activation script actually writes. `~user`
  # is the form upstream hands the shell for the ByHost path.
  wants = lib.concatMap (e: map (d: "${d} ${e.key}") e.domains) entries;
  writes =
    let
      act = config.system.activationScripts;
      pairs = map (builtins.match ".*defaults write ([^ ]+) ([^ ]+) .*") (
        lib.splitString "\n" (act.defaults.text + act.userDefaults.text)
      );
    in
    map (
      m:
      lib.replaceStrings [ "~${config.system.primaryUser}" ] [ home ] (
        "${lib.elemAt m 0} ${lib.elemAt m 1}"
      )
    ) (lib.filter (m: m != null) pairs);

  prefs-status = pkgs.writeShellApplication {
    name = "prefs-status";
    text =
      builtins.readFile ./prefs-status.sh
      + lib.concatStringsSep "\n" (lib.sort (a: b: a < b) (map check entries))
      + "\n\nsummary\n";
  };
in
{
  # The declared set above is written blind, so the tool that reads it back is
  # part of the same module. Its comparison table is generated at eval rather
  # than parsed at run time, which keeps `defaults` and bash the only things it
  # needs on the machine.
  environment.systemPackages = [ prefs-status ];

  # `targets` is the one place this module restates something upstream owns.
  # Checking it against the activation script costs nothing at build time and
  # means the tool cannot silently report a clean machine because it stopped
  # looking at a whole group.
  assertions =
    let
      unchecked = lib.subtractLists wants writes;
      unwritten = lib.subtractLists writes wants;
    in
    [
      {
        assertion = unchecked == [ ] && unwritten == [ ];
        message =
          "preferences.nix: `targets` no longer matches nix-darwin's writes."
          + lib.optionalString (
            unchecked != [ ]
          ) "\n  written, never checked: ${lib.concatStringsSep ", " unchecked}"
          + lib.optionalString (
            unwritten != [ ]
          ) "\n  checked, never written: ${lib.concatStringsSep ", " unwritten}";
      }
    ];

  system.defaults.NSGlobalDomain = {
    # Faster than the Keyboard pane can express: the unit is a 15 ms tick, and
    # the sliders bottom out at 2 (30 ms) and 15 (225 ms).
    KeyRepeat = 1;
    InitialKeyRepeat = 10;

    # Holding a key repeats it instead of opening the accent picker — the
    # thing that makes vim's hjkl usable outside a terminal.
    ApplePressAndHoldEnabled = false;

    # Media keys on the top row; F1–F12 behind fn. A bare fn press does
    # nothing, which is what leaves the key for Karabiner to bind
    # (KEYBOARD.md).
    "com.apple.keyboard.fnState" = false;

    # Every text substitution off. These fire in any Cocoa text field, so the
    # quote and dash ones corrupt code pasted through one.
    NSAutomaticCapitalizationEnabled = false;
    NSAutomaticSpellingCorrectionEnabled = false;
    NSAutomaticQuoteSubstitutionEnabled = false;
    NSAutomaticDashSubstitutionEnabled = false;
    NSAutomaticPeriodSubstitutionEnabled = false;
    NSAutomaticInlinePredictionEnabled = false;

    # NSGlobalDomain twins of two trackpad-domain keys below. The Trackpad
    # pane writes both halves of each pair and there is no rule about which
    # half a given consumer reads, so the two that change behaviour here are
    # written from both sides. TrackpadRightClick needs only its
    # trackpad-domain half; that one already works with this side unset.
    "com.apple.mouse.tapBehavior" = 1; # trackpad.Clicking
    "com.apple.trackpad.forceClick" = false; # trackpad.ForceSuppressed

    # Tracking speed, 0–3. No trackpad-domain equivalent; this is the only
    # place it lives.
    "com.apple.trackpad.scaling" = 2.5;

    # Two-finger horizontal swipe stays a scroll instead of browser
    # back/forward.
    AppleEnableSwipeNavigateWithScrolls = false;

    # Save dialogs open expanded. Two keys because older apps read the
    # unsuffixed one.
    NSNavPanelExpandedStateForSaveMode = true;
    NSNavPanelExpandedStateForSaveMode2 = true;

    NSDocumentSaveNewDocumentsToCloud = false;

    # Covers the menu-bar clock too, so none of the menuExtraClock keys are
    # declared.
    AppleICUForce24HourTime = true;

    # Auto light/dark rather than pinned dark, because AppleInterfaceStyle's
    # type accepts only "Dark" — there is no value meaning light, and going
    # back needs `defaults delete -g AppleInterfaceStyle` by hand.
    AppleInterfaceStyleSwitchesAutomatically = true;

    # Clicking the scrollbar track jumps to that spot rather than paging.
    AppleScrollerPagingBehavior = true;

    NSWindowResizeTime = 0.1;

    # cmd-ctrl-drag moves a window from anywhere in it, not just the title bar.
    NSWindowShouldDragOnGesture = true;
  };

  # Written to both com.apple.AppleMultitouchTrackpad and the
  # driver.AppleBluetoothMultitouch.trackpad twin.
  system.defaults.trackpad = {
    Clicking = true;

    # Light click, no force touch: no hard-press-to-look-up and no haptic
    # second detent.
    ForceSuppressed = true;
    FirstClickThreshold = 0;

    TrackpadRightClick = true;

    # Three-finger tap does not open Look Up.
    TrackpadThreeFingerTapGesture = 0;
  };

  # Enum of strings here; nix-darwin maps it to the integer the plist holds.
  system.defaults.hitoolbox.AppleFnUsageType = "Do Nothing";

  system.defaults.dock = {
    autohide = true;

    # Animation multiplier only. autohide-delay is deliberately left alone:
    # the default wait is what stops a left-edge Dock popping out every time
    # the cursor reaches a window edge.
    autohide-time-modifier = 0.25;

    tilesize = 54;
    orientation = "left";
    mineffect = "scale";

    # Running applications only — no pinned icons, so launching is Spotlight's
    # job. The persistent-apps list survives untouched in the plist and comes
    # back if this goes false.
    static-only = true;

    expose-animation-duration = 0.5;

    # Every corner disabled (1). Only the bottom right was ever assigned — to
    # Quick Note, which fires on any stray throw of the cursor down there —
    # but naming all four means neither System Settings nor a macOS upgrade
    # can quietly hand one of them back out.
    wvous-tl-corner = 1;
    wvous-tr-corner = 1;
    wvous-bl-corner = 1;
    wvous-br-corner = 1;
  };

  # Clicking the wallpaper no longer sweeps every window aside.
  system.defaults.WindowManager.EnableStandardClickToShowDesktop = false;

  # Bools here, but the plist holds 18 for shown and 24 for hidden;
  # BatteryShowPercentage is the exception and stores a plain bool.
  system.defaults.controlcenter = {
    BatteryShowPercentage = true;
    Bluetooth = true;
    Display = true;
  };

  system.defaults.loginwindow.GuestEnabled = false;

  system.defaults.screensaver = {
    askForPassword = true;
    askForPasswordDelay = 1;
  };

  # NVRAM, not a preference domain, so `just prefs-status` does not cover it.
  system.startup.chime = false;
}
