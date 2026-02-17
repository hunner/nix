{ config, pkgs, modulesPath, openclaw-flake, ... }:

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
  sops.secrets.openclaw-env = {
    owner = "ruil";
    mode = "0400";
  };

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
    linger = true;
    hashedPasswordFile = config.sops.secrets.hashedPassword-ruil.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB5+cFZ52qQft4ionKvdHkNM7lmj3x7vSiG/KqGvZ9JP hunter@haugens.org"
    ];
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.ruil = { ... }: {
    imports = [ openclaw-flake.homeManagerModules.openclaw ];

    home.stateVersion = "25.11";

    # Keep credentials in ruil-owned files to avoid root-only bot access.
    programs.openclaw = {
      enable = true;
      config = {
        gateway.mode = "local";
        channels.discord.enabled = true;
        agents.defaults.model.primary = "zai/glm-4.7";
      };
    };

    # openclaw onboarding can exceed Node's default old-space limit on 1 GiB hosts.
    home.sessionVariables.NODE_OPTIONS = "--max-old-space-size=1536";

    # Environment file is provisioned by sops-nix (`sops.secrets.openclaw-env`).
    systemd.user.services.openclaw-gateway = {
      Install.WantedBy = [ "default.target" ];
      Service.Environment = [ "NODE_OPTIONS=--max-old-space-size=1536" ];
      Service.EnvironmentFile = [ config.sops.secrets.openclaw-env.path ];
    };
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

  # Tailscale
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    extraUpFlags = [
      "--accept-dns"
      "--accept-routes"
    ];
  };

  programs.zsh.enable = true;

  # Add swap on small VPS instances to avoid OOM-kill loops.
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 4096; # MiB
    }
  ];

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };
}
