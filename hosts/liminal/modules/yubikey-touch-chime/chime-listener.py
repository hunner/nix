#!/usr/bin/env python3
"""Play a chime whenever the YubiKey starts waiting for a physical touch.

Reads the event stream that yubikey-touch-detector publishes on its unix
socket ($XDG_RUNTIME_DIR/yubikey-touch-detector.socket) and plays a short WAV
through PipeWire on each touch-request *start*.

The detector's wire format is a stream of fixed 5-byte ASCII tokens with no
delimiter -- "GPG_1" when a touch starts being awaited, "GPG_0" when it ends,
and likewise U2F_1/U2F_0 and HMAC_1/HMAC_0. Tokens can arrive coalesced in a
single read, so this parses a byte buffer in 5-char chunks rather than
assuming one token per recv().

There is no notification daemon on this box by design: sound is the whole
alert. So the reader must never block. Playback is fire-and-forget via
subprocess and the socket keeps being read while the chime sounds.

Environment:
  YUBIKEY_TOUCH_SOCKET  socket path (default: $XDG_RUNTIME_DIR/...)
  YUBIKEY_CHIME_WAV     WAV to play (required)
  YUBIKEY_CHIME_PLAYER  player binary (default: pw-play)
  YUBIKEY_CHIME_EVENTS  comma-separated start events (default: GPG_1)
"""

import os
import socket
import subprocess
import sys
import time

TOKEN_LEN = 5
# Re-arm window. gpg-agent can ask for several signatures back to back; one
# chime per touch is the point, but a burst inside this window is one alert.
DEBOUNCE_S = 1.0
# Reconnect backoff, seconds. The detector may not be up yet at login, and it
# restarts independently of this service.
BACKOFF_START = 0.5
BACKOFF_MAX = 30.0


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def play(player, wav, state):
    now = time.monotonic()
    if now - state["last"] < DEBOUNCE_S:
        log("touch event within debounce window; not re-chiming")
        return
    state["last"] = now
    # Reap any finished predecessor so we do not accumulate zombies.
    prev = state.get("proc")
    if prev is not None and prev.poll() is None:
        # Still playing; let it finish rather than stacking a second voice.
        return
    try:
        state["proc"] = subprocess.Popen(
            [player, wav],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        log("touch requested -> chime")
    except OSError as e:
        log(f"could not start {player}: {e}")


def consume(buf, wanted, player, wav, state):
    """Drain whole 5-byte tokens out of buf; return the unparsed remainder."""
    while len(buf) >= TOKEN_LEN:
        token = buf[:TOKEN_LEN].decode("ascii", "replace")
        buf = buf[TOKEN_LEN:]
        log(f"event {token}")
        if token in wanted:
            play(player, wav, state)
    return buf


def main():
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    sock_path = os.environ.get(
        "YUBIKEY_TOUCH_SOCKET", f"{runtime}/yubikey-touch-detector.socket"
    )
    wav = os.environ.get("YUBIKEY_CHIME_WAV")
    if not wav:
        sys.exit("YUBIKEY_CHIME_WAV is not set")
    player = os.environ.get("YUBIKEY_CHIME_PLAYER", "pw-play")
    wanted = {
        e.strip()
        for e in os.environ.get("YUBIKEY_CHIME_EVENTS", "GPG_1").split(",")
        if e.strip()
    }
    state = {"last": 0.0, "proc": None}
    backoff = BACKOFF_START

    log(f"listening on {sock_path}, chiming {sorted(wanted)} with {player} {wav}")
    while True:
        try:
            s = socket.socket(socket.AF_UNIX)
            s.connect(sock_path)
        except OSError as e:
            log(f"cannot connect to {sock_path} ({e}); retrying in {backoff:.1f}s")
            time.sleep(backoff)
            backoff = min(backoff * 2, BACKOFF_MAX)
            continue

        log("connected to touch detector")
        backoff = BACKOFF_START
        buf = b""
        try:
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    log("detector closed the connection")
                    break
                buf = consume(buf + chunk, wanted, player, wav, state)
        except OSError as e:
            log(f"read error: {e}")
        finally:
            s.close()
        time.sleep(backoff)


if __name__ == "__main__":
    main()
