# Config for framework16
{ config, pkgs, lib, ... }:

let
  impermanence = builtins.fetchTarball "https://github.com/nix-community/impermanence/archive/master.tar.gz";
  unstable = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz") {
    config = config.nixpkgs.config;
    overlays = config.nixpkgs.overlays;
  };
in
{
  imports =
    [
      ./hardware-configuration.nix
      "${impermanence}/nixos.nix"
    ];

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    #initrd.luks.devices."cryptroot".device = "/dev/disk/by-partlabel/cryptroot";
    #initrd.luks.devices."cryptswap".device = "/dev/disk/by-partlabel/cryptswap";

    resumeDevice = "/dev/nvme0n1p2";
    kernelParams = [
      "resume_offset=0"
      "mem_sleep_default=deep"
    ];
  };

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
  programs.zsh.enable = true;
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";
  services.tailscale.enable = true;
  hardware.brillo.enable = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
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

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable bluetooth
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # Enable sound with pipewire.
  hardware.pulseaudio.enable = false;
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
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.hunner = {
    isNormalUser = true;
    description = "Hunter Haugen";
    extraGroups = [ "docker" "networkmanager" "wheel" "audio" "video" ];
    hashedPassword = "$y$j9T$hLqdzlz7dbJZgUnKs.eo3/$25s/2X18vGtDKj53qD1sn/.Omp/6CBJWbn7d9KAiOK7";
    shell = pkgs.zsh;
    packages = with pkgs; [
      neovim
      asdf-vm
      pinentry-gtk2
      gnupg
      unstable.zoom-us
      firefox-devedition
      nodejs
      slack
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
    hsetroot
    redshift
    flameshot
    #code-cursor
    unstable.code-cursor
    pwvucontrol
    pamixer
    helvum
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
    package = unstable.direnv;
    nix-direnv.enable = true;
    nix-direnv.package = unstable.nix-direnv;
  };
  programs._1password.enable = true;
  programs._1password-gui.enable = true;
  programs._1password-gui.polkitPolicyOwners = [ "hunner" ];

  fonts.packages = with pkgs; [
    nerdfonts
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
  security.polkit.enable = true;

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
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

}
# vim: ft=nix ai
