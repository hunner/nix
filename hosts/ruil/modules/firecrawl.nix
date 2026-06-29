{ config, pkgs, ... }:

let
  domain = "firecrawl.hunner.dev";
  port = 3002;
  stateDir = "/var/lib/firecrawl";
  composeFile = "/etc/firecrawl/docker-compose.yaml";
  dockerCompose = pkgs.writeShellScript "firecrawl-docker-compose" ''
    set -euo pipefail
    exec ${pkgs.docker_29}/bin/docker compose -f ${composeFile} "$@"
  '';
in
{
  sops.secrets.firecrawl-env = {
    owner = "root";
    mode = "0400";
  };

  virtualisation.docker = {
    enable = true;
    package = pkgs.docker_29;
  };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0755 root root - -"
  ];

  environment.etc."firecrawl/docker-compose.yaml".source = ./firecrawl/docker-compose.yaml;

  environment.systemPackages = [ pkgs.docker-compose ];

  systemd.services.firecrawl = {
    description = "Firecrawl web scraping API";
    after = [ "docker.service" "network-online.target" ];
    requires = [ "docker.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = stateDir;
      EnvironmentFile = [ config.sops.secrets.firecrawl-env.path ];
      ExecStart = "${dockerCompose} up -d --remove-orphans";
      ExecStop = "${dockerCompose} down";
      TimeoutStartSec = "10min";
    };
  };

  # Firecrawl on firecrawl.hunner.dev (Cloudflare proxy -> nginx -> localhost:3002).
  services.nginx.virtualHosts.${domain} = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = ''
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        client_max_body_size 25m;
      '';
    };
  };
}