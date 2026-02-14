{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    ./hardware-configuration.nix
    (modulesPath + "/virtualisation/digital-ocean-config.nix")
  ];

  networking.hostName = "ruil";

  system.stateVersion = "25.11";

  # Enable nix flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # sops-nix secrets
  sops.defaultSopsFile = ./secrets/config.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.hashedPassword-hunner.neededForUsers = true;
  sops.secrets.hashedPassword-ruil.neededForUsers = true;
  sops.secrets.hashedPassword-root.neededForUsers = true;

  # SSH key from DO metadata, shared across all users
  users.users.root = {
    hashedPasswordFile = config.sops.secrets.hashedPassword-root.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB5+cFZ52qQft4ionKvdHkNM7lmj3x7vSiG/KqGvZ9JP hunter@haugens.org"
    ];
  };

  users.users.hunner = {
    uid = 1000;
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.sops.secrets.hashedPassword-hunner.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB5+cFZ52qQft4ionKvdHkNM7lmj3x7vSiG/KqGvZ9JP hunter@haugens.org"
    ];
  };

  users.users.ruil = {
    uid = 1001;
    isNormalUser = true;
    hashedPasswordFile = config.sops.secrets.hashedPassword-ruil.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB5+cFZ52qQft4ionKvdHkNM7lmj3x7vSiG/KqGvZ9JP hunter@haugens.org"
    ];
  };

  # Packages
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
    htop
    tmux
  ];

  # SSH — keys only, no password auth
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "prohibit-password";
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.settings.KbdInteractiveAuthentication = false;

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };
}
