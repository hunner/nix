# Audible alert when the YubiKey is waiting for a physical touch.
#
# Everything for this feature lives under this directory:
#   default.nix         — NixOS module (two user services + the WAV derivation)
#   make-chime.py       — builds the WAV at Nix build time, stdlib only
#   chime-listener.py   — reads the detector socket, plays the WAV
#
# Why this exists: the signing subkey has UIF Sign=on, so every git commit
# needs a physical touch. The only signal the key gives is an LED blink that
# is easy to miss behind a monitor, and the touch window is 15 seconds. The
# first sign that anything went wrong is the *retry* popping a PIN box, by
# which point a minute is gone. Sound is the whole alert here: this box runs
# no notification daemon and does not want one, so the detector's -libnotify
# and -dbus modes are both left off.
#
# How the detection works. yubikey-touch-detector puts an inotify watch on
# every ~/.gnupg/private-keys-v1.d/*.key stub and emits GPG_1 when one is
# opened with the card busy, GPG_0 when the operation ends. The process that
# opens those files is *hunner's gpg-agent*, never the client, so this fires
# for a signature requested by any process on the machine — including one
# running as the `agents` user over the restricted extra socket (see
# ../agents-gpg-bridge). Measured 2026-09-10: GPG_1 arrived 423 ms after a
# local `gpg --sign`, and 442 ms after a sign issued through the extra
# socket. Both are comfortably inside the 15 s window.
#
# False positives were looked for and not found. Across ~10 minutes with the
# detector up, `gpg --list-keys`, `--list-secret-keys`, `--export`,
# `--verify`, `--card-status` and `gpg-connect-agent KEYINFO --list` produced
# no events at all, and 75 s of pure idle produced none either. Every GPG_1
# observed corresponded to a real touch request.
#
# One side effect worth knowing about, because it is not documented anywhere
# obvious and it touches ssh. The detector's SSH watcher does not observe the
# ssh-agent socket, it *interposes* on it: at startup it renames
# $XDG_RUNTIME_DIR/gnupg/S.gpg-agent.ssh to S.gpg-agent.ssh.original and binds
# its own proxy in that place. Two consequences, both measured 2026-09-10:
#
#   - The proxy is created 0755 where gpg-agent's own socket was 0700. Only
#     the 0700 on $XDG_RUNTIME_DIR itself keeps another local user out --
#     verified that `agents` still gets EACCES through it. Nothing to fix
#     today, but do not ever loosen /run/user/1000, and keep it in mind if the
#     extra-socket relocation pattern is ever copied to the ssh socket.
#   - On SIGTERM it puts the original socket back and ssh-add keeps working;
#     verified. A SIGKILL or a crash would leave the dead proxy in place and
#     break ssh auth until the unit restarts, which is why Restart=always
#     below is load-bearing rather than tidiness.
#
# There is no flag to run the detector without the SSH watcher (--help lists
# only -dbus, -libnotify, -no-socket, -stdout, -v, -version), so this comes
# with the package.
#
# Test it by hand with:
#   echo test | gpg --sign --local-user 0xEF99694AA599DDAD > /dev/null
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # The chime itself, generated at build time so no binary blob lives in the
  # repo. ~0.54 s, two struck tones a rising fifth apart (A5 -> E6). It is
  # deliberately bell-like rather than a beep: this is the only audible alert
  # on the desktop, so it has to be recognisable out of the corner of the ear.
  chimeWav =
    pkgs.runCommand "yubikey-touch-chime.wav"
      { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        python3 ${./make-chime.py} "$out"
      '';

  # Both units are defined system-wide because there is no home-manager here,
  # so without this they would also be instantiated for any other user that
  # ever gets a systemd user manager (`agents` does, transiently, under sudo).
  # Only hunner's session owns the YubiKey and the PipeWire sink.
  onlyHunner = { ConditionUser = "hunner"; };
in
{
  environment.systemPackages = [ pkgs.yubikey-touch-detector ];

  # Watches the gpg private-key stubs (plus U2F and HMAC on /dev) and
  # publishes events on $XDG_RUNTIME_DIR/yubikey-touch-detector.socket.
  # -no-socket is *not* passed: the socket is the entire interface used here.
  systemd.user.services.yubikey-touch-detector = {
    description = "Detect when the YubiKey is waiting for a touch";
    wantedBy = [ "default.target" ];
    unitConfig = onlyHunner;
    serviceConfig = {
      ExecStart = "${pkgs.yubikey-touch-detector}/bin/yubikey-touch-detector";
      Restart = "always";
      RestartSec = 2;
    };
  };

  # Plays the chime on each touch request. Kept separate from the detector so
  # that restarting either one does not disturb the other; the listener
  # reconnects on its own with backoff, so start ordering is a hint, not a
  # requirement.
  systemd.user.services.yubikey-touch-chime = {
    description = "Chime when the YubiKey is waiting for a touch";
    wantedBy = [ "default.target" ];
    after = [ "yubikey-touch-detector.service" ];
    wants = [ "yubikey-touch-detector.service" ];
    unitConfig = onlyHunner;
    environment = {
      YUBIKEY_CHIME_WAV = "${chimeWav}";
      YUBIKEY_CHIME_PLAYER = "${pkgs.pipewire}/bin/pw-play";
      # GPG only. U2F_1/HMAC_1 are available from the same socket if a
      # browser-touch chime is ever wanted; adding them here is the whole
      # change (comma-separated).
      YUBIKEY_CHIME_EVENTS = "GPG_1";
    };
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${./chime-listener.py}";
      Restart = "always";
      RestartSec = 2;
    };
  };
}
