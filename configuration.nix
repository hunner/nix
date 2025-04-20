# Enable the OpenSSH daemon.
# services.openssh.enable = true;

# Open ports in the firewall.
# networking.firewall.allowedTCPPorts = [ ... ];
# networking.firewall.allowedUDPPorts = [ ... ];
# Or disable the firewall altogether.
# networking.firewall.enable = false;

# Copy the NixOS configuration file and link it from the resulting system
# (/run/current-system/configuration.nix). This is useful in case you
# accidentally delete configuration.nix.
# system.copySystemConfiguration = true;
{ config, pkgs, lib, ... }:

let
  impermanence = builtins.fetchTarball "https://github.com/nix-community/impermanence/archive/master.tar.gz";
in
{
  imports =
    [
      ./hardware-configuration.nix
      "${impermanence}/nixos.nix"
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable ZFS support
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "tank" ];
  #boot.zfs.requestEncryptionCredentials = true;

  # ZFS filesystem configuration
  fileSystems = {
    #"/" = {
    #  device = "rpool/local/root";
    #  fsType = "zfs";
    #};

    #"/boot" = {
    #  device = "/dev/disk/by-uuid/10CD-4CB5";
    #  fsType = "vfat";
    #  options = [ "fmask=0077" "dmask=0077" ];
    #};

    #"/nix" = {
    #  device = "rpool/local/nix";
    #  fsType = "zfs";
    #};

    #"/home" = {
    #  device = "rpool/safe/home";
    #  fsType = "zfs";
    #};

    "/persist" = {
      device = "rpool/safe/persist";
      fsType = "zfs";
      neededForBoot = true;
    };

    #"/var/lib/docker" = {
    #  device = "rpool/docker";
    #  fsType = "zfs";
    #  options = [ "zfsutil" ];
    #  neededForBoot = true;
    #};
  };

  swapDevices = [{
    randomEncryption = true;
    device = "/dev/disk/by-partuuid/1a5d6a96-0558-4623-bf52-e7523f5afe0e";
  }];

  # Impermanence configuration
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
      "/etc/nix/id_rsa"
    ];
  };

  # Create tmpfs for root to implement impermanence
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    zfs rollback -r rpool/local/root@blank
  '';

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
  ];

  # User configuration
  users.users.hunner = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" "networkmanager" ];
    initialPassword = "a";
    shell = pkgs.zsh;
  };

  # Home manager integration for persistent home configuration (optional)
  # home-manager.users.hunner = { pkgs, ... }: {
  #   home.persistence."/persist/home/hunner" = {
  #     directories = [
  #       "Downloads"
  #       "Documents"
  #       "Pictures"
  #       "Videos"
  #       ".ssh"
  #       ".config"
  #     ];
  #     files = [
  #       ".bash_history"
  #     ];
  #   };
  # };

  # Networking
  networking = {
    hostName = "cryostation";
    hostId = "a20e391e"; # Required for ZFS
    networkmanager.enable = true;
  };

  # Time zone and locale
  time.timeZone = "America/Los_Angeles"; # Adjust to your timezone
  i18n.defaultLocale = "en_US.UTF-8";

  programs.zsh.enable = true;
  services.openssh.enable = true;
  # Enable ZFS auto-snapshot service
  # services.zfs.autoSnapshot = {
  #   enable = true;
  #   frequent = 4;
  #   hourly = 24;
  #   daily = 7;
  #   weekly = 4;
  #   monthly = 12;
  # };

  # This value determines the NixOS release
  system.stateVersion = "24.11";
}

