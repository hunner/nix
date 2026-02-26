{ config, ... }:

{
  sops.secrets.vaultwarden-env = {
    owner = "vaultwarden";
    mode = "0400";
  };

  # Vaultwarden on warden.hunner.dev
  services.vaultwarden = {
    enable = true;
    configureNginx = true;
    domain = "warden.hunner.dev";
    # SMTP and admin token are sourced from the sops-managed env file.
    environmentFile = [ config.sops.secrets.vaultwarden-env.path ];
    config = {
      SIGNUPS_ALLOWED = true;
      INVITATIONS_ALLOWED = true;
    };
  };

  # ACME certificate for Cloudflare Full (strict) origin TLS.
  services.nginx.virtualHosts."warden.hunner.dev".enableACME = true;
}
