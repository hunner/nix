# AirPlay 2 output to the "Office" HomePod mini stereo pair.
#
# Everything for this stack lives under this directory:
#   default.nix          — NixOS module
#   airplay-bridge.py    — supervisor: PipeWire sink -> both speakers, in sync
#   airplay-pair.py      — optional HomeKit PIN pairing (see below)
#   airplay_common.py    — mDNS lookup and credential storage
#
# Why this exists rather than PipeWire's own AirPlay support:
# libpipewire-module-raop-sink only speaks AirPlay 1. It discovers HomePods
# happily and they even appear in the output picker, but HomePod OS 26 answers
# the RAOP OPTIONS and ANNOUNCE and then silently drops the SETUP, so nothing
# ever plays. Native AirPlay 2 — HomeKit pairing, encrypted RTSP, binary-plist
# SETUP, ChaCha20-Poly1305 audio, PTP timing — is a different protocol, and
# cliairplay is the maintained Linux implementation of it.
#
# Why two sessions for one pair: a stereo pair is not one endpoint on the wire.
# Apple senders open a session to each member, send full stereo to both, and
# hold them together with one PTP grandmaster and one agreed start instant.
# Each speaker takes its own channel from the stereo it receives. Addressing
# only the "leader" plays one speaker.
#
# Timing is not optional. A HomePod refuses an AirPlay 2 session that offers
# NTP timing: the SETUP simply never gets a reply. It needs a real PTP
# grandmaster, which means UDP 319/320, which means a privileged process. That
# is airplay-ptp.service below, and it is what makes the whole thing work.
#
# No pairing is required. HomePods accept anonymous transient pairing, so the
# bridge just connects. airplay-pair exists only for a receiver that refuses
# transient pairing — an Apple TV, or a speaker with Require Password on. If
# credentials are ever stored for a speaker the bridge uses them instead.
#
# Setup: pick "Office (AirPlay 2)" in the GNOME output chooser and play
# something. The bridge connects on demand and releases the speakers when
# audio stops.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # PipeWire node name of the bridge sink, and what the picker shows.
  sinkNode = "airplay-office";
  sinkDescription = "Office (AirPlay 2)";

  # Home names of every speaker in the pair, exactly as the Home app shows
  # them — these are matched against the mDNS `_airplay._tcp` service names.
  speakers = [
    "Office"
    "Office (2)"
  ];

  # Name this host announces to the speakers.
  senderName = "liminal";

  airplayTools = pkgs.stdenv.mkDerivation {
    name = "airplay-bridge-tools";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      runHook preInstall

      install -Dm644 ${./airplay_common.py} $out/libexec/airplay/airplay_common.py
      install -Dm755 ${./airplay-bridge.py} $out/libexec/airplay/airplay-bridge.py
      install -Dm755 ${./airplay-pair.py}   $out/libexec/airplay/airplay-pair.py

      for tool in bridge pair; do
        makeWrapper ${lib.getExe pkgs.python3} $out/bin/airplay-$tool \
          --add-flags $out/libexec/airplay/airplay-$tool.py \
          --set CLIAIRPLAY ${lib.getExe pkgs.cliairplay} \
          --set PW_RECORD ${pkgs.pipewire}/bin/pw-record \
          --set PW_DUMP ${pkgs.pipewire}/bin/pw-dump \
          --prefix PATH : ${lib.makeBinPath [ pkgs.avahi ]}
      done

      runHook postInstall
    '';
  };
in
{
  environment.systemPackages = [
    airplayTools
    pkgs.cliairplay
  ];

  # A null sink is what the desktop actually selects; the bridge reads its
  # monitor. Without this there is nothing to pick in the output chooser.
  services.pipewire.extraConfig.pipewire."99-airplay-sink" = {
    "context.objects" = [
      {
        factory = "adapter";
        args = {
          "factory.name" = "support.null-audio-sink";
          "node.name" = sinkNode;
          "node.description" = sinkDescription;
          "media.class" = "Audio/Sink";
          "audio.position" = [ "FL" "FR" ];
          # AirPlay carries 44.1 kHz; matching here avoids a resample.
          "audio.rate" = 44100;
          # Leave the monitor at unity. With this on, the desktop fader is
          # baked into the samples we capture, so a volume change only becomes
          # audible once the ~2 s already in flight has drained. The bridge
          # instead watches the fader and sends the speakers an AirPlay volume
          # command, which arrives on the control channel and takes effect at
          # once — so the PCM must stay unscaled or the two would compound.
          "monitor.channel-volumes" = false;
        };
      }
    ];
  };

  # One PTP grandmaster for the whole host. Only one process can hold UDP
  # 319/320, and every member of a sync group must slave to the same clock, so
  # this runs once and the per-speaker sessions attach to it over shared
  # memory. Without it the speakers never agree on time and HomePods play
  # silence even though the session looks healthy.
  systemd.services.airplay-ptp = {
    description = "AirPlay 2 PTP grandmaster clock";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.cliairplay} --ptp-daemon";
      Restart = "always";
      RestartSec = 5;

      DynamicUser = true;
      # DynamicUser implies PrivateTmp, which would hide the /dev/shm segment
      # this daemon publishes from the user session that has to read it.
      PrivateTmp = false;

      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      SystemCallArchitectures = "native";
      SystemCallFilter = [ "@system-service" ];
    };
  };

  # The bridge lives in the user session because that is where PipeWire is.
  systemd.user.services.airplay-bridge = {
    description = "Bridge ${sinkDescription} to the HomePod pair";
    wantedBy = [ "default.target" ];
    wants = [ "pipewire.service" ];
    after = [ "pipewire.service" ];

    serviceConfig = {
      ExecStart = lib.concatStringsSep " " (
        [
          "${airplayTools}/bin/airplay-bridge"
          "--sink ${sinkNode}"
          "--sender-name ${senderName}"
        ]
        ++ map (name: "--device '${name}'") speakers
      );
      Restart = "always";
      RestartSec = 5;
      # Nothing here is realtime; the audio path is pw-record and cliairplay.
      Nice = -5;
    };
  };
}
