"""Shared helpers for the AirPlay 2 bridge and its pairing tool.

Both tools need the same two things: find a receiver on the LAN by its Home
name, and read/write the HomeKit credentials that a one-time PIN pairing
produced.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

# Where `airplay-pair` stores credentials and `airplay-bridge` reads them.
STATE_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
    "airplay-bridge",
)


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def creds_path(device: str) -> str:
    """One credentials file per receiver, named after a slug of its Home name."""
    slug = re.sub(r"[^A-Za-z0-9_-]+", "-", device).strip("-").lower()
    return os.path.join(STATE_DIR, f"{slug}.json")


def load_creds(device: str) -> dict | None:
    """Return stored HomeKit credentials for a speaker, or None if unpaired.

    Unpaired is the normal case. A HomePod accepts anonymous "transient"
    pairing, so credentials are only needed for a receiver that refuses it —
    an Apple TV, or a speaker with Require Password turned on. Missing
    credentials are therefore not an error; malformed ones are.
    """
    path = creds_path(device)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            creds = json.load(fh)
    except FileNotFoundError:
        return None
    if not creds.get("auth") or not creds.get("dacp"):
        raise ValueError(f"{path} is missing the 'auth' or 'dacp' field")
    return creds


def stored_dacp(device: str) -> str | None:
    """Return the pairing identity already on disk, or None if there is none.

    pair-setup signs this identity into the credentials it hands back, and
    every later session must present the same one, so re-pairing a speaker has
    to reuse it. A speaker that was never paired simply has none: that is the
    normal case here, not an error, which is why this does not go through
    load_creds().
    """
    try:
        with open(creds_path(device), "r", encoding="utf-8") as fh:
            return json.load(fh).get("dacp") or None
    except (OSError, ValueError):
        return None


def save_creds(device: str, dacp: str, auth: str) -> str:
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    path = creds_path(device)
    # HomeKit credentials are a long-lived secret: keep them owner-only.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump({"device": device, "dacp": dacp, "auth": auth}, fh, indent=2)
        fh.write("\n")
    return path


def _unescape(name: str) -> str:
    r"""Undo avahi's \NNN decimal escaping in the -p (parsable) output."""
    return re.sub(r"\\(\d{3})", lambda m: chr(int(m.group(1))), name)


def browse(timeout: int = 20) -> dict:
    """Browse `_airplay._tcp` once and index every receiver by Home name.

    Each entry carries the address, port and mDNS TXT records. The TXT set
    matters: it is what cliairplay reads to pick the protocol, the timing mode
    and the codec, so it is passed through verbatim rather than reconstructed.

    One browse serves every speaker. Scanning per speaker would spend the
    settle time again for each, which is most of the budget for bringing a
    stereo pair up together.
    """
    avahi = shutil.which("avahi-browse")
    if not avahi:
        raise RuntimeError("avahi-browse not found; is services.avahi enabled?")

    proc = subprocess.run(
        [avahi, "-rtp", "_airplay._tcp"],
        capture_output=True,
        text=True,
        timeout=timeout,
    )

    found = {}
    for line in proc.stdout.splitlines():
        # =;iface;proto;name;type;domain;host;address;port;"k=v" "k=v" ...
        if not line.startswith("="):
            continue
        fields = line.split(";")
        if len(fields) < 10 or fields[2] != "IPv4":
            continue

        name = _unescape(fields[3])
        txt = " ".join(
            part.strip('"') for part in re.findall(r'"[^"]*"', fields[9])
        )
        found[name] = {
            "name": name,
            "host": fields[6],
            "address": fields[7],
            "port": int(fields[8]),
            "txt": txt,
        }
    return found


def resolve(device: str, timeout: int = 20) -> dict:
    """Find one `_airplay._tcp` receiver by Home name."""
    try:
        return browse(timeout)[device]
    except KeyError:
        raise LookupError(
            f"no _airplay._tcp receiver named {device!r} on the LAN"
        ) from None
