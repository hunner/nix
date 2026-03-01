{ pkgs, ... }:

{
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
      StateDirectory = "etherpad-lite";
      WorkingDirectory = "/var/lib/etherpad-lite";
      ExecStart = "${pkgs.etherpad-lite}/bin/etherpad-lite --settings /etc/etherpad-lite/settings.json --sessionkey /var/lib/etherpad-lite/SESSIONKEY.txt --apikey /var/lib/etherpad-lite/APIKEY.txt";
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
