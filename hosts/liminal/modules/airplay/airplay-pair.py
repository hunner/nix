#!/usr/bin/env python3
"""One-time HomeKit pairing with an AirPlay 2 receiver.

HomePods refuse the anonymous "transient" pairing that Sonos and friends
accept: they answer the handshake with a 200 and then never reply to the
session SETUP. They need a real HomeKit pair-setup, where the speaker reads a
PIN out loud and the sender keeps the resulting credentials.

Run this once per speaker. A stereo pair is two speakers, so pair both.

    airplay-pair "Office"
    airplay-pair "Office (2)"
"""

from __future__ import annotations

import argparse
import os
import secrets
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from airplay_common import creds_path, log, resolve, save_creds, stored_dacp

CLIAIRPLAY = os.environ.get("CLIAIRPLAY", "cliairplay")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("device", help='Home name of the speaker, e.g. "Office"')
    ap.add_argument(
        "--force",
        action="store_true",
        help="re-pair even if credentials already exist",
    )
    args = ap.parse_args()

    if not args.force and os.path.exists(creds_path(args.device)):
        log(f"{args.device}: already paired ({creds_path(args.device)})")
        log("Pass --force to pair again.")
        return 0

    target = resolve(args.device)
    log(f"{args.device}: found at {target['address']}:{target['port']}")

    # The pairing identity is signed into the credentials, so pair-setup and
    # every later session must present the same one. Reuse it when re-pairing;
    # mint one on a speaker that has never been paired.
    dacp = stored_dacp(args.device) or secrets.token_hex(8).upper()

    # cliairplay prompts for the PIN itself and logs progress on stderr. Both
    # are captured so this tool owns the conversation; the log is replayed only
    # if something goes wrong.
    proc = subprocess.Popen(
        [
            CLIAIRPLAY,
            "--pair-setup",
            "--port", str(target["port"]),
            "--dacp", dacp,
            target["address"],
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    # Popen was asked for all three pipes, so it created all three. Bind them
    # to names the type checker can follow.
    stdin, stdout, stderr = proc.stdin, proc.stdout, proc.stderr
    if stdin is None or stdout is None or stderr is None:
        proc.kill()
        raise RuntimeError("subprocess pipes were not created")

    diagnostics: list[str] = []
    threading.Thread(target=lambda: diagnostics.extend(stderr), daemon=True).start()

    # The speaker only announces its PIN once cliairplay has asked for one.
    time.sleep(2)
    log("")
    log(f"{args.device} should now be announcing a four-digit AirPlay code.")
    log("If you hear nothing, check the Home app: the speaker's settings must")
    log('allow speaker access from this network.')
    log("")

    try:
        pin = input("Enter the PIN: ").strip()
    except (EOFError, KeyboardInterrupt):
        proc.kill()
        log("\nAborted.")
        return 1

    try:
        stdin.write(pin + "\n")
        stdin.flush()
    except (BrokenPipeError, ValueError):
        pass

    credentials = None
    for line in stdout:
        line = line.rstrip("\n")
        if line.startswith("CREDENTIALS: "):
            credentials = line.split(": ", 1)[1].strip()
    proc.wait()

    if proc.returncode != 0 or not credentials:
        log(f"{args.device}: pairing failed")
        for line in diagnostics:
            log(line.rstrip("\n"))
        return 1

    path = save_creds(args.device, dacp, credentials)
    log(f"{args.device}: paired, credentials saved to {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
