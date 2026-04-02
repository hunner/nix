{ pkgs, ... }:

let
  domain = "epub.hunner.dev";
  booksDir = "/var/lib/flow/books";
  port = 3010;
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/flow 0755 root root - -"
    "d ${booksDir} 0755 root root - -"
  ];

  systemd.services.flow = {
    description = "Flow EPUB reader";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      Environment = [
        "PORT=${toString port}"
        "NEXT_TELEMETRY_DISABLED=1"
        "NEXT_PUBLIC_DROPBOX_CLIENT_ID="
        "DROPBOX_CLIENT_SECRET="
      ];
      ExecStart = "${pkgs.flow}/bin/flow";
      Restart = "on-failure";
      RestartSec = "5s";
      WorkingDirectory = "${pkgs.flow}/share/flow/apps/reader";
    };
  };

  # Flow on epub.hunner.dev (Cloudflare proxy/tunnel -> nginx -> localhost:3010).
  services.nginx.virtualHosts.${domain} = {
    enableACME = true;
    forceSSL = true;
    locations."^~ /books/" = {
      alias = "${booksDir}/";
      extraConfig = ''
        autoindex on;
        add_header Access-Control-Allow-Origin "*" always;
      '';
    };
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
