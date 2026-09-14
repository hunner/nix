# Let the `agents` user sign with hunner's YubiKey, via gpg-agent's own
# restricted extra socket. No socat bridge, no key material copied anywhere.
#
# Everything for this feature lives under this directory:
#   default.nix            — NixOS module (this file)
#   setup-agents-gpg.sh    — one-shot host-side setup, run as hunner
#
# The shape: gpg-agent's `extra-socket` is the socket it serves in *restricted
# mode* — signing and decryption are allowed, key management and anything that
# would leak agent internals are refused. It is normally created next to the
# main socket in $XDG_RUNTIME_DIR/gnupg, which is 0700 hunner, so no other
# user can even traverse to it. Relocating it to /run/agents-gpg is what makes
# it reachable. On the `agents` side a `%Assuan%` redirect file stands in for
# S.gpg-agent, so gpg there connects to hunner's agent instead of autostarting
# a keyless one of its own.
#
# Why the extra chmod unit, when a default ACL on the directory ought to do it.
# It does not, and this was measured rather than assumed (2026-09-10):
# gpg-agent chmods every socket it binds to 0700. On a file carrying an ACL
# that call rewrites the *mask*, so an inherited `user:agents:rw-` entry comes
# back `#effective:---` and agents gets EACCES on connect(). Verified both
# ways: with the default ACL alone connect() raised PermissionError; with the
# mask restored afterwards it returned "OK Pleased to meet you".
#
# So the permission has to be reapplied after gpg-agent creates the socket,
# and plain POSIX group bits do the job without any ACL at all — hunner and
# agents already share group `ai` (agents' primary group), and the setgid bit
# below makes the socket inherit it. All that is left is turning 0700 into
# 0660, which agents-gpg-socket.service does.
#
# Why PathChanged on the directory rather than PathExists on the socket:
# PathExists is level-triggered against a condition the service does not
# clear, so it re-fires the instant the oneshot exits. Measured: it fired five
# times in 60 ms and then died with 'unit-start-limit-hit', after which a real
# socket recreation was missed entirely. PathChanged on the parent directory
# fires once per create and once per delete and stays active (waiting).
#
# Enabling this is NOT just a rebuild — see setup-agents-gpg.sh. In
# particular, gpg-agent *refuses to start at all* if the extra-socket
# directory is missing ("error binding socket ... No such file or directory",
# then exit 2 with no agent), so the `extra-socket` line must not be live in
# ~/.gnupg/gpg-agent.conf before this module has created /run/agents-gpg.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  socketDir = "/run/agents-gpg";
  socketPath = "${socketDir}/S.gpg-agent.extra";

  # See the note in ../yubikey-touch-chime: user units here are not scoped by
  # home-manager, so say who they are for.
  onlyHunner = { ConditionUser = "hunner"; };

  fixSocketPerms = pkgs.writeShellScript "fix-agents-gpg-socket" ''
    set -u
    sock=${socketPath}
    # Fires on deletion too; nothing to do then.
    [ -S "$sock" ] || exit 0
    # The setgid bit on the directory should already have done this; repeat it
    # so a directory that lost the bit still yields a working socket.
    ${pkgs.coreutils}/bin/chgrp ai "$sock" 2>/dev/null || true
    ${pkgs.coreutils}/bin/chmod 0660 "$sock"
  '';
in
{
  # /run is tmpfs, so this is recreated every boot, and `nixos-rebuild switch`
  # runs systemd-tmpfiles as part of activation — the directory appears
  # immediately on switch, without a reboot.
  #
  # 2750: setgid so the socket gpg-agent binds here inherits group `ai`
  # (verified 2026-09-10), and no o+x because only agents needs to get in.
  systemd.tmpfiles.rules = [
    "d ${socketDir} 2750 hunner ai -"
  ];

  systemd.user.paths.agents-gpg-socket = {
    description = "Watch for gpg-agent recreating the agents-facing extra socket";
    wantedBy = [ "default.target" ];
    unitConfig = onlyHunner;
    pathConfig = {
      PathChanged = socketDir;
      Unit = "agents-gpg-socket.service";
    };
  };

  systemd.user.services.agents-gpg-socket = {
    description = "Make the gpg-agent extra socket reachable by the agents user";
    # Also run once at login, so a socket that already exists (agent started
    # before the path unit was watching) is fixed up without waiting for the
    # next agent restart.
    wantedBy = [ "default.target" ];
    unitConfig = onlyHunner;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${fixSocketPerms}";
    };
  };
}
