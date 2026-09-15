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
in

{
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "slice";
  networking.localHostName = "slice";
  networking.computerName = "slice";

  # darwin takes an integer here, not a "26.05"-style string.
  system.stateVersion = 6;

  # Required before nix-darwin will evaluate any user-scoped option.
  system.primaryUser = "hunner";

  users.users.hunner = {
    name = "hunner";
    home = "/Users/hunner";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "root" "hunner" ];

  # Written out in full: nix-darwin's reattach option cannot pass ignore_ssh.
  security.pam.services.sudo_local.text = lib.mkForce ''
    auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so ignore_ssh
    auth       sufficient     pam_tid.so
  '';

  system.defaults = {

    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";

      KeyRepeat = 2;
      InitialKeyRepeat = 15;

      # The trackpad.Clicking half of tap-to-click; both are needed.
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

      # Deliberately empty: an app dragged into the Dock is reverted on the
      # next rebuild. Pin apps by adding them here.
      persistent-apps = [ ];
    };

    trackpad = {
      Clicking = true;
    };

    universalaccess = {
      reduceMotion = true;
      reduceTransparency = true;
      closeViewScrollWheelToggle = true;
      mouseDriverCursorSize = 2.0; # types.float, so 2.0 and not 2
    };

    WindowManager = {
      EnableStandardClickToShowDesktop = false;
      EnableTiledWindowMargins = false;
    };

    CustomUserPreferences = {
      NSGlobalDomain = {
        AppleAccentColor = 1;
        AppleReduceDesktopTinting = false; # false means tinting is allowed
      };

      # 0 is "Always". macOS 26 moved the real control here; nix-darwin manages
      # only the legacy _HIHideMenuBar half above.
      "com.apple.controlcenter" = {
        AutoHideMenuBarOption = 0;
      };
    };
  };

  environment.systemPackages = with pkgs; [
    tmux
    #claude-code
    devenv
    just
    pinentry_mac

    fzf
    neovim
    kanata
    sketchybar
  ];

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

    casks = [
      "alfred"
      "amethyst"
      "firefox"
      "firefox@developer-edition"
      "ghostty"
      "space-rabbit"
      "claude-code"
      "claude"
      "font-liberation-mono-for-powerline"
      "font-liberation-nerd-font"
      "font-jetbrains-mono-nerd-font"
      "font-hack-nerd-font"
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
      upgrade = true;
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
        "${kanataPackage}/bin/kanata"
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

  # -- Manual steps after a switch, in order ----------------------------------
  #
  #   1. Approve the driver extension: System Settings > General > Login Items
  #      & Extensions > Driver Extensions, enable
  #      Karabiner-VirtualHIDDevice-Manager. `systemextensionsctl list` should
  #      then read [activated enabled].
  #   2. Put the kanata config at ~/.config/kanata/kanata.kbd.
  #   3. Grant Input Monitoring to the kanata binary. No prompt will ever
  #      appear -- tccd will not raise a dialog for a root daemon. Add it by
  #      hand: System Settings > Privacy & Security > Input Monitoring, "+",
  #      Cmd-Shift-G, paste the output of `readlink -f $(which kanata)`.
  #   4. Grant Accessibility to the same path. Separate grant, needed for the
  #      mouse actions (movemouse-*, mwheel-*, mlft/mrgt/mmid), which go via
  #      CGEventPost and fail silently without it.
  #   5. `sudo launchctl kickstart -k system/org.nixos.kanata`, then check
  #      /var/log/kanata.log.
  #
  # Both grants are pinned to the exact store path, so every kanata bump voids
  # them and needs steps 3-5 again. Prune the stale entries while in those
  # panes; nothing else does.
}
