# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, impermanence, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      "${impermanence}/nixos.nix"
    ];

  #boot.kernelPackages = pkgs.linuxKernel.packages.linux_6_7;
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "bitrot" ];
  hardware.enableAllFirmware = true;
  nixpkgs.config.allowUnfree = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems = {
    "/persist" = {
      device = "rpool/safe/persist";
      fsType = "zfs";
      neededForBoot = true;
    };
  };
  # TODO postResumeCommands after update
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    zfs rollback -r rpool/local/root@blank
  '';

  networking.hostName = "zima"; # Define your hostname.
  networking.hostId = "78599900";
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;
  virtualisation.docker.enable = true;


  services.cron = {
    enable = true;
    systemCronJobs = [
      "*/5 * * * *      hunner    widget drive zima $(zfs list -o available -H /bitrot) free"
    ];
  };
  

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # sops-nix secrets
  sops.defaultSopsFile = ./secrets/config.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.hashedPassword.neededForUsers = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.hunner = {
    uid = 1000;
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ]; # Enable ‘sudo’ for the user.
    hashedPasswordFile = config.sops.secrets.hashedPassword.path;
    packages = with pkgs; [
      tree
    ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    git
    wget
    tmux
    awscli2
    nix-search-cli
    smartmontools
    python3
    ffmpeg
    jq
    sanoid
    unrar
    unzip
    docker-compose
    lzop # for syncoid
    pv # for syncoid
    mbuffer # for syncoid
    restic
    openssl
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  services.zfs.autoScrub = {
    enable = true;
    interval = "weekly";
    pools = [ "bitrot" ];
  };

  services.sanoid = {
    enable = true;

    templates.production = {
      frequently = 0;
      hourly = 12;
      daily = 10; 
      monthly = 2;
      yearly = 1;
      autosnap = true;
      autoprune = true;
      recursive = true;
    };

    datasets."bitrot" = {
      useTemplate = [ "production" ];
    };

    datasets."rpool/safe" = {
      useTemplate = [ "production" ];
    };
  };

  users.users.backup = {
    uid = 1001;
    isNormalUser = true;
    description = "Backup replication user";
    shell = pkgs.bash;
    packages = with pkgs; [
      sanoid
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDtgW+cxPjo70k6dkYPqzP0FR5G9zvbArp/85ZHRrMRL backup@cryochamber"
    ];
  };
  services.syncoid = {
    enable = true;
    user = "backup";
    sshKey = "/var/lib/syncoid/.ssh/id_ed25519";
    commonArgs = [
      #"--sshoption=StrictHostKeyChecking=off"
      "--sshoption=UserKnownHostsFile=/var/lib/syncoid/.ssh/known_hosts"
      "--sshoption=IdentitiesOnly=yes"
      "--no-sync-snap"
    ];
    commands."backup-zima-bitrot" = {
      source = "bitrot";
      target = "root@cryochamber:tank/backups/zima/bitrot";
      recursive = true;
    };
    commands."backup-zima-rpool-safe" = {
      source = "rpool/safe";
      target = "root@cryochamber:tank/backups/zima/rpool-safe";
      recursive = true;
    };
  };
  # This was needed when trying to get the backup user to work instead of using
  # root; probably not needed now
  systemd.services.syncoid-backup-zima-bitrot.serviceConfig = {
    Environment = [
      "HOME=/var/lib/syncoid"
      "SSH_AUTH_SOCK="
    ];
    ExecStartPre = [
      "+${pkgs.coreutils}/bin/mkdir -p /var/lib/syncoid/.ssh"
      "+${pkgs.coreutils}/bin/cp /home/backup/.ssh/id_ed25519 /var/lib/syncoid/.ssh/"
      "+${pkgs.coreutils}/bin/cp /home/backup/.ssh/known_hosts /var/lib/syncoid/.ssh/"
      "+${pkgs.coreutils}/bin/chown -R backup:syncoid /var/lib/syncoid/.ssh"
      "+${pkgs.coreutils}/bin/chmod 700 /var/lib/syncoid/.ssh"
      "+${pkgs.coreutils}/bin/chmod 600 /var/lib/syncoid/.ssh/id_ed25519"
    ];
  };

  services.tailscale.enable = true;

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.Macs = [
    "hmac-sha2-256"
    "hmac-sha2-512-etm@openssh.com"
    "hmac-sha2-256-etm@openssh.com"
    "umac-128-etm@openssh.com"
  ];
  services.openssh.settings.AcceptEnv = "LANG LC_*";

  # Old style
  #environment.etc = {
  #  nixos.source = "/persist/etc/nixos";
  #  adjtime.source = "/persist/etc/adjtime";
  #  NIXOS.source = "/persist/etc/NIXOS";
  #  machine-id.source = "/persist/etc/machine-id";
  #  "ssh/ssh_host_rsa_key".source = "/persist/etc/ssh/ssh_host_rsa_key";
  #  "ssh/ssh_host_rsa_key.pub".source = "/persist/etc/ssh/ssh_host_rsa_key.pub";
  #  "ssh/ssh_host_ed25519_key".source = "/persist/etc/ssh/ssh_host_ed25519_key";
  #  "ssh/ssh_host_ed25519_key.pub".source = "/persist/etc/ssh/ssh_host_ed25519_key.pub";
  #};

  # https://www.reddit.com/r/NixOS/comments/13j64qh/how_to_add_impermanence_afterwards/?rdt=38929 also suggests
  # - /var/log
  # - /var/tmp
  # - /var/lib/nixos
  # but to do that I'd need something other than environment.etc

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/root"
      "/etc/nixos"
      "/etc/ssh"
      #"/var/log"
      #"/var/lib/nixos"
      #"/var/lib/systemd/coredump"
      #"/etc/NetworkManager/system-connections"
    ];
    files = [
      "/etc/machine-id"
    ];
  };
  security.sudo.extraConfig = ''
    # rollback results in sudo lectures after each reboot
    Defaults lecture = never
  '';

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 32400 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "23.11"; # Did you read the comment?

}

