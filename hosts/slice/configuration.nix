{
  config,
  lib,
  pkgs,
  ...
}:

let
  kanataPackage = pkgs.kanata;

  # kanata is version-coupled to this driver, so take it from passthru rather
  # than pinning a version here.
  karabinerDriver = kanataPackage.darwinDriver;
  karabinerDriverVersion = kanataPackage.darwinDriverVersion;

  # A DriverKit extension can only be activated by a real (non-symlink) app
  # under /Applications, so the Manager bundle is copied there at activation.
  vhidManagerDir = "/Applications/.Nix-Kanata";
  vhidManagerApp = ".Karabiner-VirtualHIDDevice-Manager.app";
  vhidManagerBin = "${vhidManagerDir}/${vhidManagerApp}/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager";

  vhidDaemonBin = "${karabinerDriver}/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon";

  # Absolute: kanata runs as root and would otherwise look in root's HOME.
  # The .kbd itself lives in the dotfiles repo, not here.
  kanataConfigFile = "/Users/hunner/.config/kanata/kanata.kbd";

  # kanata is copied out of the store to a fixed path, and the daemon launches
  # that copy rather than the store binary.
  #
  # TCC pins Input Monitoring and Accessibility to a path *and* a code
  # identity, so a store path that moves on every rebuild voids both grants and
  # kanata then crash-loops on "needs macOS Input Monitoring permission". A
  # fixed path alone is not enough: measured on 2026-10-05, two separate store
  # paths for the same kanata 1.12.0 had different cdhashes (f19ca249 vs
  # f665ee5f), so the identity moves even when the version does not.
  #
  # Re-signing the copy with one certificate that outlives the store path is
  # what makes the grants stick, because TCC then records the certificate as
  # the designated requirement instead of the binary's hash. Signing is skipped
  # when the identity is absent, leaving the store's own ad-hoc signature in
  # place; kanata still runs, the grants just need redoing on each bump as
  # before. See the manual steps at the bottom of this file.
  kanataStableDir = "/usr/local/libexec/nix-kanata";
  kanataStableBin = "${kanataStableDir}/kanata";
  kanataSigningIdentity = "nix-kanata-signing";

  llamaServer = lib.getExe' pkgs.llama-cpp "llama-server";
  llamaModelsDir = "/Users/hunner/.local/share/llama-swap/models";
  llamaSwapPort = 11434;
  llamaSwapConfig = (pkgs.formats.yaml { }).generate "llama-swap.yaml" {
    # Loading 13.2 GiB cold overruns the default health-check window and
    # llama-swap then kills a server that was going to come up fine.
    healthCheckTimeout = 900;

    models."qwen3.8:27b-unleashed" = {
      aliases = [ "unleashed" ];

      ttl = 600;

      # Flags follow liminal's unleashed entry, with three deliberate changes:
      #
      #   -c 65536, not 262144. Weights leave roughly 5 GiB of the 18.2 GiB
      #   Metal budget for KV, and a 256k window does not fit in that. This is
      #   the first knob to turn down if llama-server dies on allocation, and
      #   the first to raise if the harness starts hitting the context limit.
      #
      #   --spec-draft-p-min 0.8, not 0.75. The gating figure in liminal's
      #   comment was picked for a bandwidth-starved iGPU; the M5 datapoint in
      #   that same comment (7.2 -> 10.5 t/s) used 0.8. Worth re-benchmarking
      #   on this machine rather than trusting either number.
      #
      # MTP drafting needs no second model: the Unleashed quants keep the MTP
      # tensors, which is why this repo was chosen over a plain Unsloth quant.
      #
      # n-max swept on this machine 2026-09-24, three 256-token code-generation
      # runs each at temp 1.0, mean decode and mean draft acceptance:
      #
      #   n-max  2   15.79 t/s   88.9%
      #   n-max  4   15.72 t/s   83.0%
      #   n-max  8   14.39 t/s   72.8%
      #   n-max 12   14.10 t/s   71.4%
      #
      # Acceptance falls as the draft deepens and the wasted compute costs more
      # than the extra accepted tokens earn, so 2 stands and 4 is within noise.
      # liminal's note that the 890M peaked at 2 holds here; the Strix Halo's 12
      # does not transfer. Beware benchmarking on predictable text: "count to
      # 40" drafts at 100% acceptance and reports ~16.5 t/s, which flatters
      # every setting and hides exactly this effect.
      cmd = "${llamaServer} --port \${PORT}"
        + " -m ${llamaModelsDir}/Qwen3.8-27B-Unleashed-UD-Q3_K_XL.gguf"
        + " -c 65536 -ngl 999 -fa on --jinja --parallel 1"
        + " -b 2048 -ub 512 --cache-reuse 256"
        + " --spec-type draft-mtp --spec-draft-n-max 2 --spec-draft-p-min 0.8"
        + " --cache-type-k q4_0 --cache-type-v q4_0"
        + " --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 --repeat-penalty 1.0";
    };
  };

  # AeroSpace is run from a local fork while three fixes are in flight
  # upstream: the workspace swap on summon (#603), focus-monitor re-asserting
  # macOS focus, and focusing the requested window rather than the app's key
  # window on multi-monitor (#101). Source and branch:
  #   ~/git/AeroSpace, branch swap-workspaces-on-summon
  #
  # Symlinked rather than built here: the fork needs Swift 6.4 and nixpkgs
  # ships 5.10 on darwin, so it is built by hand with `swift build` and
  # packaged with the script in that repo. Consequence: if that build is
  # missing these links dangle and AeroSpace will not start. Drop this
  # override to go back to the released nixpkgs build.
  aerospaceFork = pkgs.runCommand "aerospace-fork" { } ''
    mkdir -p $out/Applications $out/bin
    ln -s /Users/hunner/git/AeroSpace/.build/AeroSpace.app $out/Applications/AeroSpace.app
    ln -s /Users/hunner/git/AeroSpace/.build/debug/aerospace $out/bin/aerospace
  '';

  aerospaceWorkspaces =
    (map (n: { key = toString n; ws = toString n; }) (lib.range 1 9))
    ++ [ { key = "0"; ws = "10"; } ];

  aerospaceWorkspaceBindings = lib.listToAttrs (
    lib.concatMap
      ({ key, ws }: [
        (lib.nameValuePair "alt-${key}" "summon-workspace ${ws}")
        (lib.nameValuePair "alt-shift-${key}" "move-node-to-workspace ${ws}")
      ])
      aerospaceWorkspaces
  );
in

{
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "slice";
  networking.localHostName = "slice";
  networking.computerName = "slice";

  # darwin takes an integer here, not a "26.05"-style string.
  system.stateVersion = 6;

  system.primaryUser = "hunner";
  users.users.hunner = {
    name = "hunner";
    home = "/Users/hunner";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "root" "hunner" ];

  security.pam.services.sudo_local.text = lib.mkForce ''
    auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so ignore_ssh
    auth       sufficient     pam_tid.so
  '';

  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      "com.apple.mouse.tapBehavior" = 1;
      # Natural scrolling, off.
      "com.apple.swipescrolldirection" = false;
      AppleSpacesSwitchOnActivate = false;
      # Only half the setting on macOS 26; see com.apple.controlcenter below.
      _HIHideMenuBar = true;
    };

    dock = {
      autohide = true;
      launchanim = false;
      mru-spaces = false;
      show-recents = false;
      tilesize = 45;

      # AeroSpace parks hidden windows off-screen, which makes Mission
      # Control render them tiny. Grouping by application is upstream's
      # documented workaround.
      expose-group-apps = true;

      # Deliberately empty: an app dragged into the Dock is reverted on the
      # next rebuild. Pin apps by adding them here.
      persistent-apps = [ ];
    };

    spaces = {
      # true = one Space spans all displays, i.e. "Displays have separate
      # Spaces" OFF. AeroSpace's guide recommends this: with it on, AeroSpace
      # hits real focus bugs on multi-monitor. The cost is that native
      # fullscreen on one display blanks the others. Needs a logout to apply.
      spans-displays = true;
    };

    trackpad = {
      Clicking = true;
    };

    universalaccess = {
      reduceMotion = false;
      reduceTransparency = true;
      closeViewScrollWheelToggle = true;
      mouseDriverCursorSize = 2.0;
    };

    WindowManager = {
      EnableStandardClickToShowDesktop = false;
      EnableTiledWindowMargins = false;
    };

    CustomUserPreferences = {
      NSGlobalDomain = {
        AppleAccentColor = 1;
        AppleReduceDesktopTinting = false;
      };

      # 0 is "Always". macOS 26 moved the real control here; nix-darwin manages
      # only the legacy _HIHideMenuBar half above.
      "com.apple.controlcenter" = {
        AutoHideMenuBarOption = 0;
      };
    };
  };

  services.aerospace = {
    enable = true;
    package = aerospaceFork;

    settings = {
      enable-normalization-flatten-containers = true;
      enable-normalization-opposite-orientation-for-nested-containers = true;
      accordion-padding = 30;
      default-root-container-layout = "tiles";
      default-root-container-orientation = "auto";
      on-focused-monitor-changed = [ "move-mouse monitor-lazy-center" ];

      gaps = {
        inner.horizontal = 0;
        inner.vertical = 0;
        outer.left = 0;
        outer.bottom = 0;
        outer.right = 0;

        # Clear the sketchybar strip, which is 32px tall and pinned to the top
        # (see ~/.config/sketchybar/sketchybarrc).
        #
        # Zero on the built-in display: the notch already reserves a 32px strip
        # there, and AeroSpace measures gaps from the visible frame, which
        # starts below it. Adding another 32 stacked up to a 64px gap. This is
        # the same reason Amethyst needed disable-padding-on-builtin-display.
        #
        # The pattern is a case-insensitive substring match on the monitor name
        # ("Built-in Retina Display"); the bare trailing value is the default
        # for every other monitor.
        outer.top = [ { monitor."built-in" = 0; } 32 ];
      };

      # Deliberately no `after-startup-command = ["exec-and-forget sketchybar"]`:
      # upstream suggests it for people with nothing supervising sketchybar, but
      # launchd.agents.sketchybar below already owns that process.
      #
      # Upstream's suggestion here is `sketchybar --trigger ...`, which does not
      # work: this runs from AeroSpace's launchd agent, which nix-darwin gives
      # no PATH at all, so a bare `sketchybar` is not found and the bar silently
      # never updates. The script is called by absolute path and resolves both
      # binaries absolutely for the same reason.
      #
      # It also does more than a trigger could: with two monitors the bar is
      # drawn on both, and a single set of items would mirror the same state to
      # each. The script assigns every workspace item to the display its
      # workspace currently lives on, so each bar shows only its own monitor's
      # workspaces.
      exec-on-workspace-change = [
        "/bin/sh"
        "-c"
        "/Users/hunner/.config/sketchybar/plugins/aerospace_workspaces.sh"
      ];

      mode.main.binding = {
        alt-slash = "layout tiles horizontal vertical";
        alt-comma = "layout accordion horizontal vertical";

        # Toggle between tiling and accordion. Accordion is AeroSpace's analog
        # of i3's tabbed/stacked layouts: windows sit on top of one another and
        # focus moves between them with the ordinary focus bindings, which is
        # the nearest thing it has to xmonad's Full layout -- AeroSpace has no
        # fullscreen *layout*, only the per-window `fullscreen` command on
        # alt-f11. accordion-padding above leaves a sliver of the neighbours
        # showing so it is clear there are more windows behind.
        alt-space = "layout tiles accordion";

        alt-h = "focus left";
        alt-j = "focus down";
        alt-k = "focus up";
        alt-l = "focus right";

        alt-shift-h = "move left";
        alt-shift-j = "move down";
        alt-shift-k = "move up";
        alt-shift-l = "move right";

        alt-minus = "resize smart -50";
        alt-equal = "resize smart +50";

        alt-tab = "workspace-back-and-forth";

        # Escape hatch for strays. When a monitor loses its visible workspace,
        # AeroSpace hands it one via getStubWorkspace(), and if 1-10 are all
        # occupied it invents an 11th. Windows sitting there are unreachable
        # with only alt-1..alt-0 bound -- which is what "the windows got lost"
        # actually is. These step through every workspace that exists,
        # including invented ones, so nothing is ever stranded.
        alt-shift-n = "workspace --wrap-around next";
        alt-shift-p = "workspace --wrap-around prev";

        # The multi-monitor payoff: send the whole workspace to the next
        # display. Native Spaces are pinned to a display and cannot do this.
        alt-shift-tab = "move-workspace-to-monitor --wrap-around next";

        # Monitors, keeping the o/e/u positions used under Amethyst. The
        # argument is a monitor-pattern; a bare number is the monitor's ordinal
        # position, counted left to right, 1-based. Patterns can also be names
        # ("built-in", "main", or a regex) if ordinals ever prove unstable
        # across dock/undock.
        #
        # Note these are the letters the helm layer *emits*, so on the physical
        # keyboard they are s/d/f. Use the real option key rather than the
        # home-row alt on physical `d`: alt-e would then be the same physical
        # key twice, and the home-row mods deliberately refuse same-hand chords.
        alt-o = "focus-monitor 1";
        alt-e = "focus-monitor 2";
        alt-u = "focus-monitor 3";

        # And throw the focused window to a monitor. Focus deliberately does
        # not follow, matching follow-space-thrown-windows = 0 under Amethyst.
        alt-shift-o = "move-node-to-monitor 1";
        alt-shift-e = "move-node-to-monitor 2";
        alt-shift-u = "move-node-to-monitor 3";

        # AeroSpace's own fullscreen: the window fills its workspace inside
        # AeroSpace's tree. Unlike the green button, it does not make macOS
        # spawn a new Space, which would be invisible to AeroSpace.
        #
        # Not alt-f: readline binds alt-f to forward-word, and AeroSpace's
        # bindings are global, so it would swallow it in every shell.
        alt-f11 = "fullscreen";

        alt-shift-semicolon = "mode service";
      } // aerospaceWorkspaceBindings;

      # A sticky mode for the rarer commands, so they need no extra chords.
      # Every binding returns to main, so it cannot be got stuck in.
      mode.service.binding = {
        esc = [ "reload-config" "mode main" ];
        r = [ "flatten-workspace-tree" "mode main" ];
        f = [ "layout floating tiling" "mode main" ];
        backspace = [ "close-all-windows-but-current" "mode main" ];
        alt-shift-h = [ "join-with left" "mode main" ];
        alt-shift-j = [ "join-with down" "mode main" ];
        alt-shift-k = [ "join-with up" "mode main" ];
        alt-shift-l = [ "join-with right" "mode main" ];
      };
    };
  };

  # ===========================================================================
  # Automatic brightness
  # ===========================================================================
  #
  # "Automatically adjust brightness" (System Settings > Displays). nix-darwin
  # has no option for it, and system.defaults.CustomSystemPreferences does not
  # reach it either: the flag is a leaf inside com.apple.CoreBrightness's
  # per-display dict, and `defaults write` replaces a dict wholesale -- that
  # would discard the AutoBrightnessCurve calibration stored beside it. plutil
  # keypaths edit the single leaf, and leave the file in the binary format
  # corebrightnessd writes.
  #
  # The plist lives in root's preference domain, so this is an activation
  # script rather than a user default. Display UUIDs are enumerated rather than
  # hardcoded, so a new monitor -- or replaced hardware -- is covered without
  # editing this file.
  #
  # Nothing is written while every display already reads false, so an ordinary
  # rebuild leaves the plist alone; cfprefsd is restarted only on a real
  # change, so its cached copy cannot write the old value back afterwards. A
  # change shows up in the UI on the next login.
  system.activationScripts.postActivation.text = ''
    coreBrightnessPlist=/var/root/Library/Preferences/com.apple.CoreBrightness.plist
    if [ -f "$coreBrightnessPlist" ]; then
      autoBrightnessChanged=
      for display in $(/usr/bin/plutil -extract DisplayPreferences json -o - "$coreBrightnessPlist" 2>/dev/null | ${pkgs.jq}/bin/jq -r 'keys[]'); do
        if [ "$(/usr/bin/plutil -extract "DisplayPreferences.$display.AutoBrightnessEnable" raw -o - "$coreBrightnessPlist" 2>/dev/null)" != "false" ]; then
          /usr/bin/plutil -replace "DisplayPreferences.$display.AutoBrightnessEnable" -bool false "$coreBrightnessPlist"
          echo "automatic brightness: disabled for display $display" >&2
          autoBrightnessChanged=1
        fi
      done
      if [ -n "$autoBrightnessChanged" ]; then
        /usr/bin/killall cfprefsd || true
      fi
    fi
  '';

  environment.systemPackages = with pkgs; [
    # Local inference. llama-cpp is here for llama-server/llama-bench by hand;
    # the launchd agent below uses the store path directly.
    llama-cpp
    llama-swap
    tmux
    #claude-code
    devenv
    just
    pinentry_mac
    runpodctl

    _1password-cli
    fzf
    neovim
    kanata
    sketchybar
    bat
    ripgrep
    gh
    fd
    yt-dlp
    htop
    herdr

    # GUI Emacs for Doom. nixpkgs rather than Homebrew specifically for
    # native-comp: the darwin build bakes absolute store paths for libgccjit,
    # ld/as and libSystem into native-comp-driver-options, so packages that
    # straight.el pulls in on `doom sync` native-compile at runtime with no
    # toolchain on PATH. Emacs.app reaches /Applications/Nix Apps as a real
    # bundle (nix-darwin rsyncs --copy-unsafe-links), so Spotlight finds it.
    emacs

    # `ykman`, the YubiKey configuration CLI (OpenPGP, PIV, FIDO2, OTP slots).
    # The package name and the binary name differ. Yubico EOL-ed the Qt GUI and
    # it is gone from nixpkgs; their replacement GUI, Yubico Authenticator, is
    # Homebrew-only on darwin -- add the "yubico-authenticator" cask if a
    # graphical one is wanted alongside this.
    yubikey-manager
  ];

  # ~/.zshrc extends fpath and runs its own compinit against a version-stamped
  # dump file. nix-darwin's global compinit in /etc/zshrc runs before that and
  # writes the UNversioned ~/.zcompdump, which nix's zsh (5.9.2, and first on
  # PATH for a bare `zsh`) and the Apple login shell (/bin/zsh, 5.9) then
  # share. That cross-version dump is what broke _main_complete autoloading,
  # surfacing as "fzf-completion:NN: _main_complete: function definition file
  # not found" on every tab. Completion itself stays on; this drops only the
  # global compinit call -- the exact case the option's docs describe.
  programs.zsh.enableGlobalCompInit = false;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # nix-darwin never installs Homebrew itself; bootstrapping /opt/homebrew is a
  # manual one-time step.
  homebrew = {
    enable = true;

    # rift is a formula in the author's tap rather than a cask, and it is in
    # neither nixpkgs nor any flake, so homebrew is the only packaged route.
    # It installs both `rift` and `rift-cli`.
    #taps = [ "acsandmann/tap" ];
    #brews = [ "rift" ];

    casks = [
      "alfred"
      # Superseded by AeroSpace (services.aerospace below). Commented rather
      # than deleted so it is one keystroke to come back; onActivation.cleanup
      # is "none", so dropping a cask from this list never uninstalls it.
      #"amethyst"
      "arq"
      "claude-code"
      "claude"
      "codex"
      "docker-desktop"
      "firefox"
      "firefox@developer-edition"
      "focusrite-control-2"
      "font-liberation-mono-for-powerline"
      "font-liberation-nerd-font"
      "font-jetbrains-mono-nerd-font"
      "font-hack-nerd-font"
      "ghostty"
      "grok-build"
      "homerow"
      "linear"
      "obsidian"
      "signal"
      "slack"
      "tailscale-app"
      "twingate"
    ];

    onActivation = {
      # Conservative on purpose: "none" means a rebuild never uninstalls
      # anything that is on the machine but missing from this list. Tighten to
      # "uninstall" once the cask list is known to be complete.
      cleanup = "none";

      # Refresh cask definitions before `brew bundle` runs, so a rebuild does
      # not install from a stale tap.
      autoUpdate = true;

      # Upgrade outdated brew-managed packages during activation. Casks that
      # update themselves are skipped unless marked `greedy`, so this is a
      # no-op for Firefox Developer Edition and correct for anything added
      # later that does not self-update.
      upgrade = false;
    };
  };

  # ===========================================================================
  # kanata
  # ===========================================================================
  #
  # kanata needs the Karabiner DriverKit virtual keyboard to emit events, and a
  # root Karabiner-VirtualHIDDevice-Daemon to talk to. Neither nix-darwin nor
  # nixpkgs has a kanata service module, so the three launchd jobs below are
  # hand-written. The driver comes from nixpkgs (karabiner-dk) rather than the
  # karabiner-elements cask, because that app's grabber would fight kanata for
  # the keyboard.

  system.activationScripts.preActivation.text = ''
    # Copied rather than symlinked: macOS refuses a symlinked app under
    # /Applications. Guarded on the source path so an unchanged driver does not
    # make macOS re-evaluate the extension on every rebuild.
    kanataVhidSrc=${lib.escapeShellArg "${karabinerDriver}/Applications/${vhidManagerApp}"}
    kanataVhidDir=${lib.escapeShellArg vhidManagerDir}
    if [ "$(cat "$kanataVhidDir/.nix-source" 2>/dev/null)" != "$kanataVhidSrc" ]; then
      echo "installing Karabiner-VirtualHIDDevice-Manager ${karabinerDriverVersion} into $kanataVhidDir" >&2
      rm -rf "$kanataVhidDir"
      mkdir -p "$kanataVhidDir"
      cp -R "$kanataVhidSrc" "$kanataVhidDir/"
      printf '%s' "$kanataVhidSrc" > "$kanataVhidDir/.nix-source"
    fi

    # Install the kanata the daemon actually launches. Guarded on the source
    # path so an unchanged kanata is neither recopied nor re-signed, which
    # would churn the code identity and void the TCC grants for no reason.
    kanataSrc=${lib.escapeShellArg "${kanataPackage}/bin/kanata"}
    kanataDir=${lib.escapeShellArg kanataStableDir}
    kanataDst=${lib.escapeShellArg kanataStableBin}
    if [ "$(cat "$kanataDir/.nix-source" 2>/dev/null)" != "$kanataSrc" ]; then
      echo "installing kanata into $kanataDir" >&2
      mkdir -p "$kanataDir"
      install -m 555 "$kanataSrc" "$kanataDst.new"
      if /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
         | grep -q ${lib.escapeShellArg kanataSigningIdentity}; then
        /usr/bin/codesign --force \
          --sign ${lib.escapeShellArg kanataSigningIdentity} \
          --identifier org.nixos.kanata \
          "$kanataDst.new" >&2
      else
        echo "kanata: ${kanataSigningIdentity} not in the keychain; keeping the store signature" >&2
      fi
      # Atomic, so a running kanata keeps the inode it started from until the
      # job is restarted.
      mv -f "$kanataDst.new" "$kanataDst"
      printf '%s' "$kanataSrc" > "$kanataDir/.nix-source"
    fi
  '';

  # Idempotent activation request. No KeepAlive: until a human approves the
  # extension there is nothing to retry.
  launchd.daemons.kanata-vhid-activate = {
    script = ''
      exec ${lib.escapeShellArg vhidManagerBin} activate
    '';
    serviceConfig = {
      RunAtLoad = true;
      StandardOutPath = "/var/log/kanata-vhid-activate.log";
      StandardErrorPath = "/var/log/kanata-vhid-activate.log";
    };
  };

  launchd.daemons.kanata-vhid-daemon = {
    command = "${lib.escapeShellArg vhidDaemonBin}";
    serviceConfig = {
      ProcessType = "Interactive";
      KeepAlive = true;
      ThrottleInterval = 10;
      StandardOutPath = "/var/log/kanata-vhid-daemon.log";
      StandardErrorPath = "/var/log/kanata-vhid-daemon.log";
    };
  };

  # ProgramArguments is spelled out rather than using `command`, which would
  # wrap it in `/bin/sh -c "/bin/wait4path ... && exec ..."` -- TCC would then
  # attribute Input Monitoring to /bin/sh instead of to kanata. KeepAlive plus
  # ThrottleInterval covers the /nix/store mount race that wait4path handled.
  # KeepAlive.PathState keeps the job idle, not crash-looping, until the .kbd
  # exists.
  launchd.daemons.kanata = {
    serviceConfig = {
      ProgramArguments = [
        kanataStableBin
        "--cfg"
        kanataConfigFile
        "--no-wait"
      ];
      ProcessType = "Interactive";
      RunAtLoad = true;
      KeepAlive.PathState.${kanataConfigFile} = true;
      ThrottleInterval = 10;
      StandardOutPath = "/var/log/kanata.log";
      StandardErrorPath = "/var/log/kanata.log";
    };
  };

  # --- sketchybar ------------------------------------------------------------
  #
  # An agent, not a daemon: sketchybar is a window-server client and must run in
  # the GUI session. launchd.agents.* (not launchd.user.agents.*) writes to
  # /Library/LaunchAgents, keeping it out of the dotfiles repo.
  #
  # PATH is spelled out because a launchd agent gets launchd's minimal PATH:
  # without this the bar loads and then every plugin fails silently with
  # "sketchybar: command not found".
  #
  # ProgramArguments rather than `command` for the same TCC reason as kanata.
  launchd.agents.sketchybar =
    let
      sketchybarBin = "${pkgs.sketchybar}/bin/sketchybar";
      sketchybarConfigFile = "/Users/hunner/.config/sketchybar/sketchybarrc";
    in
    {
      serviceConfig = {
        ProgramArguments = [
          sketchybarBin
          "--config"
          sketchybarConfigFile
        ];
        EnvironmentVariables = {
          PATH = lib.concatStringsSep ":" [
            "/run/current-system/sw/bin"
            "/nix/var/nix/profiles/default/bin"
            "/Users/hunner/.nix-profile/bin"
            "/opt/homebrew/bin"
            "/opt/homebrew/sbin"
            "/usr/local/bin"
            "/usr/bin"
            "/bin"
            "/usr/sbin"
            "/sbin"
          ];
          # Plugins emit UTF-8 glyphs; launchd's default C locale mangles them.
          LANG = "en_US.UTF-8";
        };
        ProcessType = "Interactive";
        LimitLoadToSessionType = "Aqua";
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        StandardOutPath = "/Users/hunner/Library/Logs/sketchybar.log";
        StandardErrorPath = "/Users/hunner/Library/Logs/sketchybar.log";
      };
    };


  # --- llama-swap ------------------------------------------------------------
  #
  # llama-swap itself is a small proxy; it is llama-server, spawned on the first
  # request and reaped after the ttl above, that holds the memory.
  #
  # This lands in /Library/LaunchAgents but, unlike launchd.agents.sketchybar
  # below, carries no LimitLoadToSessionType, so launchd loads it into the
  # system domain and it runs as root rather than as hunner. That works because
  # the gguf is world-readable and the listener is loopback-only, but it is
  # more privilege than an inference server needs. Adding
  # LimitLoadToSessionType = "Aqua" would move it into the GUI session as
  # hunner, at the cost of only running while logged in.
  #
  # Bound to loopback on purpose. liminal's equivalent is reachable on the LAN,
  # but nothing else needs to talk to this one and the model is abliterated.
  launchd.agents.llama-swap = {
    serviceConfig = {
      ProgramArguments = [
        (lib.getExe pkgs.llama-swap)
        "--config"
        "${llamaSwapConfig}"
        "--listen"
        "127.0.0.1:${toString llamaSwapPort}"
      ];
      EnvironmentVariables = {
        # launchd gives an agent no HOME, and llama-swap writes state relative
        # to it.
        HOME = "/Users/hunner";
      };
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 10;
      StandardOutPath = "/Users/hunner/Library/Logs/llama-swap.log";
      StandardErrorPath = "/Users/hunner/Library/Logs/llama-swap.log";
    };
  };

  # -- Manual steps after a switch, in order ----------------------------------
  #
  #   1. Approve the driver extension: System Settings > General > Login Items
  #      & Extensions > Driver Extensions, enable
  #      Karabiner-VirtualHIDDevice-Manager. `systemextensionsctl list` should
  #      then read [activated enabled].
  #   2. Put the kanata config at ~/.config/kanata/kanata.kbd.
  #   3. Create the signing certificate, once. Keychain Access > Certificate
  #      Assistant > Create a Certificate: name nix-kanata-signing, identity
  #      type Self Signed Root, certificate type Code Signing, and tick "Let me
  #      override defaults" only if the System keychain is wanted. The
  #      activation script signs the copy with it whenever it is present, and
  #      says so in the rebuild output when it is missing.
  #   4. Grant Input Monitoring to /usr/local/libexec/nix-kanata/kanata. No
  #      prompt will ever appear -- tccd will not raise a dialog for a root
  #      daemon. Add it by hand: System Settings > Privacy & Security > Input
  #      Monitoring, "+", Cmd-Shift-G, paste that path.
  #   5. Grant Accessibility to the same path. Separate grant, needed for the
  #      mouse actions (movemouse-*, mwheel-*, mlft/mrgt/mmid), which go via
  #      CGEventPost and fail silently without it.
  #   6. `sudo launchctl kickstart -k system/org.nixos.kanata`, then check
  #      /var/log/kanata.log.
  #
  # Both grants point at a path this config keeps stable across rebuilds, so
  # they survive a kanata bump once the certificate from step 3 exists. Without
  # it the copy keeps the store's ad-hoc signature, whose cdhash changes on
  # every rebuild, and steps 4-6 are needed again each time. Prune stale
  # /nix/store entries left over from before this change while in those panes;
  # nothing else does.
}
