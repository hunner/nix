# Config for framework16
{ config, pkgs, lib, ... }:

let
  nixos-hardware = builtins.fetchTarball "https://github.com/NixOS/nixos-hardware/archive/master.tar.gz";
  impermanence = builtins.fetchTarball "https://github.com/nix-community/impermanence/archive/master.tar.gz";
  unstable = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz") {
    config = config.nixpkgs.config;
    overlays = config.nixpkgs.overlays;
  };
  #unstable = import nixos-unstable {
  #  #config = config.nixpkgs.config;
  #  inherit (pkgs) system;
  #};
  #hp15c = pkgs.callPackage ./pkgs/hp15c/default.nix { inherit unstable; };
  #nonpareil = pkgs.callPackage ./pkgs/nonpareil/default.nix { inherit pkgs; };
  #custom1Password = pkgs.symlinkJoin {
  #  name = "1password-gui-custom";
  #  paths = [ unstable._1password-gui ];
  #  buildInputs = [ pkgs.makeWrapper ];
  #  postBuild = ''
  #    # Create directory for our custom policy
  #    mkdir -p $out/share/polkit-1/actions/

  #    # Copy the original policy file
  #    cp ${unstable._1password-gui}/share/polkit-1/actions/com.1password.1Password.policy $out/share/polkit-1/actions/

  #    # Modify the policy file to add the annotation
  #    sed -i '/<action id="com.1password.1Password.unlock">/,/<\/action>/ s|<\/defaults>|<\/defaults>\n      <annotate key="org.freedesktop.policykit.owner">unix-user:hunner<\/annotate>|' $out/share/polkit-1/actions/com.1password.1Password.policy
  #  '';
  #};
in
{
  imports =
    [
      "${nixos-hardware}/framework/16-inch/7040-amd"
      ./hardware-configuration.nix
      "${impermanence}/nixos.nix"
    ];

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    #initrd.luks.devices."cryptroot".device = "/dev/disk/by-partlabel/disk-nvme0n1-cryptroot";
    initrd.luks.devices."cryptswap".device = "/dev/disk/by-partlabel/disk-nvme0n1-swap";

    resumeDevice = "/dev/nvme0n1p2";
    kernelParams = [
      "resume_offset=0"
      "mem_sleep_default=deep"
    ];
  };
  swapDevices = [ {
    device = "/dev/mapper/cryptswap";
  } ];
  services.fwupd.enable = true;
  hardware.framework.enableKmod = true;

  fileSystems = {
    "/" = {
      device = "none";
      fsType = "tmpfs";
      options = [ "defaults" "size=17G" "mode=755" ];
    };
    "/persist" = {
      neededForBoot = true;
    };
  };

  hardware.amdgpu = {
    opencl.enable = true;
    amdvlk.enable = true;
  };
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "amdgpu" ];
  services.ollama = {
    enable = true;
    loadModels = [ "gemma3" ];
    acceleration = "rocm";
    rocmOverrideGfx = "11.0.3";
  };

  networking.hostId = "3294c9a2"; # Required for ZFS
  networking.hostName = "liminal";
  networking.networkmanager.enable = true;
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.extraHosts =
    ''
      127.0.0.1 keycloak
    '';

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/root"
      "/etc/nixos"
      "/etc/ssh"
      "/etc/NetworkManager/system-connections"
    ];
    files = [
      "/etc/machine-id"
      #"/etc/nix/id_rsa" # Needed?
    ];
  };
  # Files are not copied to /persist during install, so need to do so manually
  #rsync -azPH /mnt/root/ /mnt/persist/root
  #rsync -azPH /mnt/etc/nixos/ /mnt/persist/etc/nixos
  #rsync -azPH /mnt/etc/ssh/ /mnt/persist/etc/ssh
  #cp /mnt/etc/machine-id /mnt/persist/etc/machine-id
  security.sudo.extraConfig = ''
    # Don't lecture after reboot
    Defaults lecture = never
  '';

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  virtualisation.docker = {
    enable = true;
    extraOptions = "--storage-driver=overlay2";
  };
  programs.hyprland.enable = true;
  programs.zsh.enable = true;
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    extraUpFlags = [
      "--accept-dns"
      "--accept-routes"
    ];
  };
  hardware.brillo.enable = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.displayManager.gdm.wayland = true;
  services.xserver.displayManager.gdm.autoSuspend = true;
  services.xserver.desktopManager.gnome.enable = true;

  services.xserver.windowManager.xmonad = {
    enable = true;
    enableContribAndExtras = true;
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-wlr
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable bluetooth
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  services.logind = {
    extraConfig = "HandlePowerKey=suspend";
    lidSwitch = "suspend";
  };

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;
  services.touchegg.enable = true;

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.hunner = {
    isNormalUser = true;
    description = "Hunter Haugen";
    extraGroups = [ "docker" "networkmanager" "wheel" "audio" "video" ];
    hashedPassword = "$y$j9T$hLqdzlz7dbJZgUnKs.eo3/$25s/2X18vGtDKj53qD1sn/.Omp/6CBJWbn7d9KAiOK7";
    shell = pkgs.zsh;
    packages = with pkgs; [
      fzf
      neovim
      asdf-vm
      pinentry-gtk2
      gnupg
      #unstable.zoom-us
      firefox-devedition
      nodejs
      slack
      mplayer
      ffmpeg
      jetbrains-toolbox
      pass
      diff-so-fancy
      webex
      unstable.zed-editor
      unstable.package-version-server
      amdgpu_top
      nixd # for zed
      goose-cli
    ];
  };
  systemd.user.services = {
    polkit-agent = {
      description = "PolKit Authentication Agent";
      wantedBy = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };
  };

  # Enable automatic login for the user.
  services.displayManager.autoLogin.enable = false;
  services.displayManager.autoLogin.user = "hunner";

  # Workaround for GNOME autologin: https://github.com/NixOS/nixpkgs/issues/103746#issuecomment-945091229
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # Install firefox.
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    jq
    yq
    bat
    git
    vim
    emacs
    wget
    curl
    htop
    tmux
    file
    ripgrep
    docker-compose
    powertop
    alacritty
    rofi
    xlockmore
    dzen2
    arandr
    xclip
    shellcheck
    scrot
    fd
    xorg.xrandr
    xorg.xsetroot
    xorg.xset
    xorg.xev
    hsetroot
    redshift
    flameshot
    unstable.code-cursor
    pwvucontrol
    pamixer
    helvum
    #hp15c
    #nonpareil
    framework-tool
    kitty # for Hyprland
    restic
    xscreensaver
    unzip
    scarlett2
    alsa-scarlett-gui
    xlsx2csv
  ];

  services.clipmenu.enable = true;
  services.picom = {
    enable = true;
    settings = {
      inactive-opacity = 1.0;
      inactive-dim = 0.0;
      inactive-opacity-override = false;
      frame-opacity = 1.0;
      inactive-dim-fixed = false;
      fading = false;  # Optional, if you want to disable fading as well
    };
  };
  programs.direnv = {
    enable = true;
    #package = unstable.direnv;
    nix-direnv.enable = true;
    #nix-direnv.package = unstable.nix-direnv;
  };
  programs._1password = {
    enable = true;
    #package = unstable._1password-cli;
  };
  programs._1password-gui = {
    enable = true;
    #package = unstable._1password-gui;
    polkitPolicyOwners = [ "hunner" ];
  };
  programs.obs-studio = {
    enable = true;
    enableVirtualCamera = true;
    plugins = with pkgs.obs-studio-plugins; [
      wlrobs
      obs-backgroundremoval
      obs-pipewire-audio-capture
      obs-ndi
    ];
  };

  fonts.packages = with pkgs; [
    nerd-fonts.droid-sans-mono
    nerd-fonts.liberation
    nerd-fonts.jetbrains-mono
    liberation_ttf
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;
  systemd.services.upower.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true; # Enable NSS lookup for .local domains
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      workstation = true;
    };
  };
  services.dbus = {
    enable = true;
    packages = [ pkgs.polkit ];
  };
  programs.dconf.enable = true;
  security.polkit.enable = true;
  services.flatpak.enable = true;
  systemd.services.flatpak-repo = {
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.flatpak ];
    script = ''
      flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    '';
  };

  services.fprintd.enable = true;
  #security.pam.services = {
  #  login.fprintAuth = true;
  #  xscreensaver.fprintAuth = true;
  #  sudo.fprintAuth = true;
  #  #gdm.fprintAuth = true;
  #  gdm-password.fprintAuth = true;
  #};

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

}
# vim: ft=nix ai
