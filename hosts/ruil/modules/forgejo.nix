{ config, ... }:

let
  domain = "git.hunner.dev";
  port = 3000;
in
{
  services.forgejo = {
    enable = true;
    user = "git";
    group = "git";
    lfs.enable = true;

    settings = {
      DEFAULT.APP_NAME = domain;

      server = {
        DOMAIN = domain;
        ROOT_URL = "https://${domain}/";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = port;
        DISABLE_SSH = false;
        SSH_DOMAIN = domain;
        SSH_PORT = 22;
      };

      session.COOKIE_SECURE = true;
      service.DISABLE_REGISTRATION = false;
    };
  };

  # Forgejo on git.hunner.dev (Cloudflare proxy -> nginx -> localhost:3000).
  services.nginx.virtualHosts.${domain} = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  users.users.git = {
    home = config.services.forgejo.stateDir;
    useDefaultShell = true;
    group = "git";
    isSystemUser = true;
  };

  users.groups.git = { };
}
