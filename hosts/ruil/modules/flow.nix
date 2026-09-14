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
        # Keep the app on loopback so it can only be reached through nginx, and
        # therefore only through the tailnet ACL in ./tailnet-only.nix.
        #
        # This needs the server.js patch in pkgs/flow/package.nix to work: the
        # vendored Next.js standalone server is Next 12 era and called
        # `server.listen(currentPort)` with no host argument, binding 0.0.0.0
        # and honouring PORT but not HOSTNAME.
        #
        # This matters more than allowedTCPPorts suggests. Tailscale installs
        # `-A ts-input -i tailscale0 -j ACCEPT` and ts-input runs before
        # nixos-fw in INPUT, so ALL tailnet traffic bypasses the NixOS firewall
        # and every 0.0.0.0 listener is reachable by any tailnet peer no matter
        # what allowedTCPPorts says. A 0.0.0.0 bind here is a real way around
        # nginx and its TLS and ACL, not a theoretical one.
        "HOSTNAME=127.0.0.1"
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
