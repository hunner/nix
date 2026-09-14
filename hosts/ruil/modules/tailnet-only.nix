{ lib, ... }:

# Restrict selected nginx vhosts to the Tailscale tailnet.
#
# Background: the public path to these names is Cloudflare proxy -> nginx, so
# every request that arrives over the internet carries a Cloudflare source
# address. An allow-list of tailnet ranges therefore denies the whole public
# path without needing to enumerate Cloudflare's ranges.
#
# Why the ACL is applied per *location* and not at server level: for vhosts with
# `enableACME`, the nginx module emits its own
# `location ^~ /.well-known/acme-challenge/` block. nginx inherits allow/deny
# from server into location, so a server-level `deny all` would be inherited by
# that challenge location and break http-01 renewal. Port 80 stays publicly
# reachable and only ever serves the ACME challenge or a 301 to https, so
# scoping the ACL to the content locations keeps certificates renewing.
#
# IMPORTANT: `protected` must list every content location each vhost actually
# serves. It was built from the generated nginx.conf, and several of these
# locations come from upstream NixOS modules (vaultwarden's notification hubs,
# searx's static/metrics/stats) rather than from this repo. If a nixpkgs bump
# adds a new location to one of these vhosts, it will NOT be covered here.
# After any channel bump, re-check with:
#
#   ssh root@ruil.hunner.dev 'CONF=$(tr "\0" "\n" < /proc/$(pgrep -o -x nginx)/cmdline \
#     | grep -oE "/nix/store/[^ ]*nginx.conf"); grep -c "deny all" $CONF'
#
# and confirm each protected vhost's locations still carry the ACL.

let
  tailnetOnly = ''
    allow 127.0.0.1;
    allow ::1;
    allow 100.64.0.0/10;
    allow fd7a:115c:a1e0::/48;
    deny all;
  '';

  protected = {
    "git.hunner.dev" = [ "/" ];
    "etherpad.hunner.dev" = [ "/" ];
    "epub.hunner.dev" = [
      "/"
      "^~ /books/"
    ];
    # warden.hunner.dev was removed here on 2026-09-02 along with the
    # vaultwarden import in ../configuration.nix. Its locations came from the
    # upstream vaultwarden module, so with that module gone the vhost no longer
    # exists and listing it here would create an empty deny-only vhost.
    "search.hunner.dev" = [
      "/"
      "/static/"
      "= /metrics"
      "^~ /stats"
    ];
  };
in
{
  services.nginx.virtualHosts = lib.mapAttrs (_name: locs: {
    locations = lib.genAttrs locs (_loc: {
      extraConfig = lib.mkAfter tailnetOnly;
    });
  }) protected;
}
