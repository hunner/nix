{ config, lib, pkgs, modulesPath, openclaw-flake, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/vaultwarden.nix
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
  sops.secrets.searx-env = {
    owner = "searx";
    mode = "0400";
  };
  sops.secrets.searx-nginx-basic-auth = {
    owner = "nginx";
    mode = "0400";
  };
  sops.secrets.openclaw-env = {
    owner = "ruil";
    mode = "0400";
  };

  # HTTPS certificates for `s.hunner.dev` (works with Cloudflare Full strict).
  security.acme = {
    acceptTerms = true;
    defaults.email = "me@hunner.dev";
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
  home-manager.users.ruil = { lib, ... }: {
    imports = [ openclaw-flake.homeManagerModules.openclaw ];

    home.stateVersion = "25.11";

    # Keep credentials in ruil-owned files to avoid root-only bot access.
    programs.openclaw.enable = true;

    # Keep ~/.openclaw/openclaw.json user-managed (Home Manager should not touch it).
    home.file.".openclaw/openclaw.json".enable = lib.mkForce false;
    home.activation.openclawConfigFiles = lib.mkForce (lib.hm.dag.entryAfter [ "openclawDirs" ] "");

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

  # SearXNG
  services.searx = {
    enable = true;
    configureNginx = true;
    redisCreateLocally = true;
    domain = "s.hunner.dev";
    environmentFile = config.sops.secrets.searx-env.path;
    settings.server.secret_key = "$SEARX_SECRET_KEY";
    settings.server.limiter = true;
    settings.server.base_url = lib.mkForce "https://s.hunner.dev/";
    settings.general.open_metrics = "$SEARX_METRICS_PASSWORD";
  };

  services.nginx.virtualHosts."s.hunner.dev" = {
    enableACME = true;
    forceSSL = true;

    # Protect metrics with nginx Basic Auth and forward the auth header so
    # SearXNG can validate `general.open_metrics`.
    locations."= /metrics" = {
      basicAuthFile = config.sops.secrets.searx-nginx-basic-auth.path;
      recommendedUwsgiSettings = true;
      uwsgiPass = "unix:${config.services.uwsgi.instance.vassals.searx.socket}";
      extraConfig = ''
        uwsgi_param  HTTP_AUTHORIZATION   $http_authorization;
        uwsgi_param  HTTP_HOST            $host;
        uwsgi_param  HTTP_CONNECTION      $http_connection;
        uwsgi_param  HTTP_X_SCHEME        $scheme;
        uwsgi_param  HTTP_X_SCRIPT_NAME   "";
        uwsgi_param  HTTP_X_REAL_IP       $remote_addr;
        uwsgi_param  HTTP_X_FORWARDED_FOR $proxy_add_x_forwarded_for;
      '';
    };

    # Protect stats endpoints (/stats, /stats/errors, /stats/checker).
    locations."^~ /stats" = {
      basicAuthFile = config.sops.secrets.searx-nginx-basic-auth.path;
      recommendedUwsgiSettings = true;
      uwsgiPass = "unix:${config.services.uwsgi.instance.vassals.searx.socket}";
      extraConfig = ''
        uwsgi_param  HTTP_HOST            $host;
        uwsgi_param  HTTP_CONNECTION      $http_connection;
        uwsgi_param  HTTP_X_SCHEME        $scheme;
        uwsgi_param  HTTP_X_SCRIPT_NAME   "";
        uwsgi_param  HTTP_X_REAL_IP       $remote_addr;
        uwsgi_param  HTTP_X_FORWARDED_FOR $proxy_add_x_forwarded_for;
      '';
    };
  };

  # Catch-all vhost so only s.hunner.dev serves SearXNG.
  services.nginx.virtualHosts."_" = {
    default = true;
    addSSL = true;
    useACMEHost = "s.hunner.dev";
    locations."/" = {
      return = "200 \"This page intentionally left blank.\"";
      extraConfig = ''
        default_type text/plain;
      '';
    };
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
    allowedTCPPorts = [ 22 80 443 ];
  };
}
