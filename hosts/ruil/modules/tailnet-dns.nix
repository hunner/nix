{ ... }:

# Split-DNS resolver for tailnet clients.
#
# Problem this solves: the tailnet-only vhosts (see ./tailnet-only.nix) are
# denied unless the request arrives from a tailnet source address. But
# git.hunner.dev and friends resolve publicly to ruil's own public IP
# (209.38.44.152), so a tailnet client that resolves them normally connects over
# the public path and gets a 403. Per-client /etc/hosts entries fix that but do
# not work on phones, so tailnet clients need real DNS instead.
#
# This runs dnsmasq on ruil's tailnet address and answers the tailnet-only names
# with the tailnet address. The owner points Tailscale split-DNS for hunner.dev
# at 100.125.223.12, so only hunner.dev lookups reach this resolver and the rest
# of each client's DNS is untouched.
#
# Why the apex is NOT hardcoded here: split-DNS sends the WHOLE hunner.dev zone
# to this resolver, including the apex and any future name. The apex is
# Cloudflare-proxied (188.114.96.0 / 188.114.97.0) rather than pointing at ruil,
# and answering it with ruil's address would serve the origin's expired
# certificate instead of Cloudflare's valid edge certificate. Pinning Cloudflare
# addresses here would also rot the moment they change. So only the four
# tailnet-only names are overridden and everything else in the zone is forwarded
# upstream, which keeps the public apex working for tailnet clients and makes
# new names work without touching this file.
#
# Exposure: this is bound ONLY to the tailnet address, never 0.0.0.0. That bind
# address is the actual access control, because Tailscale inserts
# `-A ts-input -i tailscale0 -j ACCEPT` ahead of nixos-fw, so tailnet traffic
# bypasses the NixOS firewall entirely and opening port 53 there would do
# nothing. Nothing is added to allowedTCPPorts/allowedUDPPorts, so the public
# interface has no listener on 53.

let
  tailnetIp = "100.125.223.12";

  # Names that must resolve to the tailnet for tailnet clients. Keep this in
  # step with the `protected` list in ./tailnet-only.nix.
  tailnetOnlyNames = [
    "git.hunner.dev"
    "search.hunner.dev"
    "epub.hunner.dev"
    "etherpad.hunner.dev"
  ];
in
{
  services.dnsmasq = {
    enable = true;

    # Do not let dnsmasq take over this host's own resolving. Tailscale runs
    # with --accept-dns and manages /etc/resolv.conf; hijacking it here would
    # fight tailscaled and could create a resolution loop.
    resolveLocalQueries = false;

    settings = {
      # bind-dynamic rather than bind-interfaces: tailscale0 and its address may
      # not exist yet when dnsmasq starts. bind-interfaces would make startup
      # fail in that window, bind-dynamic picks the address up when it appears.
      bind-dynamic = true;
      listen-address = tailnetIp;

      # Answer the tailnet-only names with the tailnet address. In dnsmasq
      # `address=/name/ip` also covers subdomains of that name, which is fine.
      address = map (n: "/${n}/${tailnetIp}") tailnetOnlyNames;

      # Resolve everything else (notably the hunner.dev apex) upstream. no-resolv
      # keeps dnsmasq off /etc/resolv.conf, which tailscaled points at
      # 100.100.100.100 -- forwarding back through that would loop once
      # split-DNS for hunner.dev is pointed here.
      no-resolv = true;
      server = [
        "1.1.1.1"
        "8.8.8.8"
      ];

      # Do not act as a general resolver for anything that finds its way here.
      domain-needed = true;
      bogus-priv = true;
    };
  };

  # The listen address only exists once tailscaled has configured tailscale0.
  systemd.services.dnsmasq = {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
  };
}
