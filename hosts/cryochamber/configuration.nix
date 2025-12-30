{ config, pkgs, lib, impermanence, ... }:

#zpool import -f rpool
#mount -t zfs rpool/local/root /mnt
#mkdir -p /mnt/{boot,nix,home,persist,var/lib,var/log}
#mount /dev/vda2 /mnt/boot
#mount -t zfs rpool/local/nix /mnt/nix
#mount -t zfs rpool/safe/home /mnt/home
#mount -t zfs rpool/safe/persist /mnt/persist
#mount -t zfs rpool/local/var/lib /mnt/var/lib
#mount -t zfs rpool/local/var/log /mnt/var/log

{
  imports =
    [
      ./hardware-configuration.nix
      "${impermanence}/nixos.nix"
    ];

  # Enable ZFS support
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.requestEncryptionCredentials = false;

  fileSystems = {
    "/persist" = {
      device = "rpool/safe/persist";
      fsType = "zfs";
      neededForBoot = true; # Only /persist needs to be marked as needed for boot
    };
  };

  # Import the existing ZFS pool from the second disk without formatting it
  boot.zfs.extraPools = [ "tank" ];
  boot.zfs.devNodes = "/dev/disk/by-path"; # This is neede for ZFS to find the pool at boot

  # Use GRUB with BIOS booting, whether MBR or GPT
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  boot.loader.grub.zfsSupport = true;
  boot.loader.grub.efiSupport = false;

  # Impermanence configuration
  # Set up impermanence - root filesystem will be reset on each boot
  boot.initrd.postResumeCommands = lib.mkAfter ''
    zfs rollback -r rpool/local/root@blank
  '';
  # /var/log and /var/lib ar persisted through zfs datasets, but not backed up.
  # Anything stored in /persist should get backed up.
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/root"
      "/etc/nixos"
      "/etc/ssh"
    ];
    files = [
      "/etc/machine-id"
    ];
  };
  # Files are not copied to /persist during install, so need to do so manually
  #rsync -azPH /mnt/root/ /mnt/persist/root
  #rsync -azPH /mnt/etc/nixos/ /mnt/persist/etc/nixos
  #rsync -azPH /mnt/etc/ssh/ /mnt/persist/etc/ssh
  #cp /mnt/etc/machine-id /mnt/persist/etc/machine-id

  # Swap configuration
  swapDevices = [ {
    device = "/dev/vda3";
    randomEncryption.enable = true;
  } ];

  # Basic system configuration
  networking.hostId = "5472a981"; # Required for ZFS
  networking.hostName = "cryochamber";

  # Enable networking
  networking.networkmanager.enable = true;

  # Don't lecture after reboot
  security.sudo.extraConfig = ''
    Defaults lecture = never
  '';

  # Set your time zone
  time.timeZone = "UTC";

  # Docker configuration
  virtualisation.docker = {
    enable = true;
    extraOptions = "--storage-driver=overlay2";
  };

  # System packages
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    curl
    htop
    zfs
    zsh
    tmux
    docker-compose
    lzop # for syncoid
    pv # for syncoid
    mbuffer # for syncoid
  ];

  services.zfs.autoScrub = {
    enable = true;
    interval = "weekly";
    pools = [ "tank" ];
  };

  services.sanoid = {
    enable = true;

    templates.backup = {
      frequently = 0;
      hourly = 0;
      daily = 30;
      monthly = 6;
      yearly = 3;
      autosnap = false;
      autoprune = true;
      recursive = "zfs";
    };

    datasets."tank" = {
      useTemplate = [ "backup" ];
    };

    datasets."rpool/safe" = {
      useTemplate = [ "backup" ];
    };
  };

  # sops-nix secrets
  sops.defaultSopsFile = ./secrets/config.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.hashedPassword.neededForUsers = true;

  # Define a user account
  users.users.hunner = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "networkmanager" ];
    hashedPasswordFile = config.sops.secrets.hashedPassword.path;
    shell = pkgs.zsh;
    packages = with pkgs; [
      fzf
      neovim
      devenv
      pass
      jq
      yq
      yt-dlp
      bat
      ripgrep
      fd
      shellcheck
      tldr
      unzip
      lsof
      gnupg
    ];
  };

  sops.secrets.syncoidSshKey = {
    owner = "syncoid";
    group = "syncoid";
    mode = "0400";
  };
  sops.secrets.zimaKnownHosts = {
    owner = "syncoid";
    group = "syncoid";
    mode = "0444";
  };


  services.syncoid = {
    enable = true;
    #user = "backup";
    sshKey = config.sops.secrets.syncoidSshKey.path;
    commonArgs = [
      #"--no-sync-snap"
      #"--sshoption=StrictHostKeyChecking=off"
      "--sshoption=UserKnownHostsFile=${config.sops.secrets.zimaKnownHosts.path}"
      "--sshoption=IdentitiesOnly=yes"
    ];
    commands."zima-bitrot" = {
      source = "root@zima:bitrot";
      target = "tank/backups/zima/bitrot";
      recursive = true;
      service.serviceConfig.BindReadOnlyPaths = [
        config.sops.secrets.syncoidSshKey.path
        config.sops.secrets.zimaKnownHosts.path
      ];
    };
    commands."zima-rpool-safe" = {
      source = "root@zima:rpool/safe";
      target = "tank/backups/zima/rpool-safe";
      recursive = true;
      service.serviceConfig.BindReadOnlyPaths = [
        config.sops.secrets.syncoidSshKey.path
        config.sops.secrets.zimaKnownHosts.path
      ];
    };
  };

  #systemd.services.syncoid-replication = {
  #  description = "ZFS syncoid replication";
  #  path = with pkgs; [ sanoid openssh zfs ];
  #  wants = [ "network-online.target" ];
  #  after = [ "network-online.target" "zfs.target" ];

  #  startAt = "03:00";

  #  serviceConfig = {
  #    Type = "oneshot";
  #    User = "backup";
  #    ExecStart = ''
  #      ${pkgs.sanoid}/bin/syncoid \
  #        --recursive \
  #        --create-bookmark \
  #        --sendoptions=w \
  #        --source-bwlimit=50000 \
  #        backup@zima:rpool/safe \
  #        tank/backups/zima/rpool-safe
  #    '';
  #    TimeoutStartSec = "6h";
  #  };
  #};

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  programs.zsh.enable = true;
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "prohibit-password";
  services.openssh.settings.Macs = [
    "hmac-sha2-512"
    "hmac-sha2-512-etm@openssh.com"
    "hmac-sha2-256-etm@openssh.com"
    "umac-128-etm@openssh.com"
  ];

  services.tailscale.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  system.stateVersion = "24.11";
}
