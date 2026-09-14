{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/etherpad-lite.nix
    ./modules/flow.nix
    ./modules/forgejo.nix
    ./modules/tailnet-only.nix
    ./modules/tailnet-dns.nix

    # REMOVED 2026-09-02 (owner decision: staying on 1Password).
    # ./modules/vaultwarden.nix is left in the tree but no longer imported, so
    # the service and the warden.hunner.dev vhost are both gone. The module also
    # declared sops.secrets.vaultwarden-env, which is now unused; the
    # vaultwarden-env key is still present in ./secrets/config.yaml.
    #
    # DATA IS DELIBERATELY NOT DELETED. Still on the host:
    #   /var/lib/vaultwarden                                   (live state dir)
    #   /root/backups/2026-09-02-pre-upgrade/vaultwarden-full
    #   /root/backups/2026-09-02-pre-upgrade/vaultwarden-db.sqlite3
    # Deleting those is a separate, deliberate owner decision.
    # ./modules/vaultwarden.nix

    # DISABLED 2026-09-02, not deleted -- ./modules/firecrawl.nix declares
    # `sops.secrets.firecrawl-env`, but no `firecrawl-env` key exists in
    # ./secrets/config.yaml. sops-install-secrets validates the manifest at
    # build time, so importing this module fails the build of the whole host:
    #
    #   secret firecrawl-env in .../config.yaml is not valid:
    #   the key 'firecrawl-env' cannot be found
    #
    # That made ruil undeployable, which was blocking an urgent security
    # rebuild. Firecrawl has never actually run here (no firecrawl.service on
    # the host, docker not running, no firecrawl-env in /run/secrets), so
    # commenting out the import changes no running service.
    #
    # To re-enable: add the key with `sops edit hosts/ruil/secrets/config.yaml`,
    # then uncomment the import below.
    # ./modules/firecrawl.nix
    (modulesPath + "/virtualisation/digital-ocean-config.nix")
  ];

  networking.hostName = "ruil";

  # nodejs 20 went EOL and 26.05 marks it insecure. It is pulled in by
  # pkgs.flow, whose vendored Next.js is version 12 era and is not expected to
  # run on a current Node major, so bumping it is a real port rather than a
  # version bump. Accepted here for now because flow (epub.hunner.dev) is no
  # longer reachable from the internet -- see ./modules/tailnet-only.nix -- and
  # its listener is bound to loopback, so reaching it means already being on the
  # tailnet.
  #
  # FOLLOW-UP: port flow to a supported nodejs and drop this. It is the only
  # thing keeping an EOL Node runtime on this host.
  nixpkgs.config.permittedInsecurePackages = [
    "nodejs-20.20.2"
    "nodejs-slim-20.20.2"
  ];

  system.stateVersion = "25.11";

  # Enable nix flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # Keep a little headroom so remote deploys can still complete GC/DB updates.
  nix.settings.min-free = 1024 * 1024 * 1024;
  nix.settings.max-free = 2 * 1024 * 1024 * 1024;
  nix.optimise.automatic = true;
  nix.gc.automatic = true;
  nix.gc.dates = "daily";
  nix.gc.options = "--delete-older-than 7d";

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
  #sops.secrets.openclaw-env = {
  #  owner = "ruil";
  #  mode = "0400";
  #};

  # HTTPS certificates for proxied `*.hunner.dev` sites (Cloudflare Full strict).
  security.acme = {
    acceptTerms = true;
    defaults.email = "me@hunner.dev";
  };

  # SSH key from DO metadata, shared across all users
  users.users.root = {
    hashedPasswordFile = config.sops.secrets.hashedPassword-root.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqd6VkCyGOaFVfh61+hVKOvYaCZsCChQq3c6rNH/ifG me@hunner.dev"
    ];
  };

  users.users.hunner = {
    uid = 1000;
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.sops.secrets.hashedPassword-hunner.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqd6VkCyGOaFVfh61+hVKOvYaCZsCChQq3c6rNH/ifG me@hunner.dev"
    ];
  };

  users.users.ruil = {
    uid = 1001;
    isNormalUser = true;
    hashedPasswordFile = config.sops.secrets.hashedPassword-ruil.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqd6VkCyGOaFVfh61+hVKOvYaCZsCChQq3c6rNH/ifG me@hunner.dev"
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

  services.journald.extraConfig = ''
    SystemMaxUse=200M
    RuntimeMaxUse=100M
  '';

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
    domain = "search.hunner.dev";
    environmentFile = config.sops.secrets.searx-env.path;
    settings.server.secret_key = "$SEARX_SECRET_KEY";
    settings.server.limiter = true;
    settings.server.base_url = lib.mkForce "https://search.hunner.dev/";
    settings.general.open_metrics = "$SEARX_METRICS_PASSWORD";
  };

  # The searx module points its uwsgi vassal at both a unix socket and an HTTP
  # listener, and the HTTP one defaults to ":8080" -- every interface, which
  # bypasses nginx and therefore also bypasses the tailnet ACL. nginx talks to
  # the unix socket, so pin the HTTP listener to loopback.
  services.uwsgi.instance.vassals.searx.http = lib.mkForce "127.0.0.1:8080";

  services.nginx.virtualHosts."search.hunner.dev" = {
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

  # Apex site with its own cert so Cloudflare Full (strict) sees a matching
  # origin certificate for `hunner.dev` instead of falling through to another
  # subdomain's cert.
  services.nginx.virtualHosts."hunner.dev" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      return = "200 \"This page intentionally left blank.\"";
      extraConfig = ''
        default_type text/plain;
      '';
    };
  };

  # Catch-all vhost so only explicitly configured names serve applications.
  services.nginx.virtualHosts."_" = {
    default = true;
    addSSL = true;
    useACMEHost = "hunner.dev";
    locations."/" = {
      return = "200 \"This page intentionally left blank.\"";
      extraConfig = ''
        default_type text/plain;
      '';
    };
  };

  programs.zsh.enable = true;

  boot.loader.grub.configurationLimit = 5;

  # Add swap on small VPS instances to avoid OOM-kill loops.
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 2048; # MiB
    }
  ];

  # Firewall
  #
  # 80/443 stay open because nginx still serves the public apex and the ACME
  # http-01 challenges for every vhost; the tailnet-only vhosts are gated inside
  # nginx by ./modules/tailnet-only.nix rather than at the packet filter.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 ];
    # Let Tailscale negotiate direct connections instead of relaying via DERP.
    allowedUDPPorts = [ 41641 ];
  };
}
