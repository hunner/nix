{ config, pkgs, ... }:

{
  sops.secrets.etherpad-env = {
    owner = "etherpad";
    mode = "0400";
  };

  users.users.etherpad = {
    isSystemUser = true;
    group = "etherpad";
  };
  users.groups.etherpad = { };

  environment.etc."etherpad-lite/settings.json".text = builtins.toJSON {
    ip = "127.0.0.1";
    port = 9001;
    trustProxy = true;
    dbType = "rustydb";
    dbSettings = {
      filename = "/var/lib/etherpad-lite/rusty.db";
    };
    users = {
      hunner = {
        password = "\${ETHERPAD_ADMIN_PASSWORD}";
        is_admin = true;
      };
    };
  };

  # Etherpad on etherpad.hunner.dev (Cloudflare proxy -> nginx -> localhost:9001).
  systemd.services.etherpad-lite = {
    description = "Etherpad Lite";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "etherpad";
      Group = "etherpad";
      EnvironmentFile = [ config.sops.secrets.etherpad-env.path ];
      StateDirectory = "etherpad-lite";
      WorkingDirectory = "/var/lib/etherpad-lite";
      ExecStart = "${pkgs.unstable.etherpad-lite}/bin/etherpad-lite --settings /etc/etherpad-lite/settings.json --sessionkey /var/lib/etherpad-lite/SESSIONKEY.txt --apikey /var/lib/etherpad-lite/APIKEY.txt";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # ACME certificate for Cloudflare Full (strict) origin TLS.
  services.nginx.virtualHosts."etherpad.hunner.dev" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:9001";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = ''
        proxy_read_timeout 360s;
      '';
    };
  };
}
