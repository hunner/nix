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
      service.DISABLE_REGISTRATION = true;
      repository.ENABLE_PUSH_CREATE_USER = true;
      repository.ENABLE_PUSH_CREATE_ORG = true;
    };
  };

  # Forgejo on git.hunner.dev (nginx -> localhost:3000).
  #
  # Reachable over the Tailscale tailnet only. The public path is denied by the
  # per-location ACL in ./tailnet-only.nix; see that file for the mechanism and
  # for the list of locations it covers. Git over SSH stays on the public port
  # 22, gated by SSH keys.
  services.nginx.virtualHosts.${domain} = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  # The NixOS module sets no TimeoutStartSec, so forgejo.service inherits the
  # 90s DefaultTimeoutStartSec. preStart runs `forgejo migrate` and the unit is
  # Type=notify, so that timeout covers the whole migration. Going 11.0.15 ->
  # 15.0.7 replays ~16 legacy plus 28 newer Forgejo migrations, several of which
  # drop columns and add foreign keys -- on SQLite those rewrite whole tables,
  # and this instance carries ~2400 repositories. A migration killed part way
  # through would need a restore from backup, since Forgejo refuses to run
  # against a database newer than its own schema.
  systemd.services.forgejo.serviceConfig.TimeoutStartSec = "30min";

  users.users.git = {
    home = config.services.forgejo.stateDir;
    useDefaultShell = true;
    group = "git";
    isSystemUser = true;
  };

  users.groups.git = { };
}
