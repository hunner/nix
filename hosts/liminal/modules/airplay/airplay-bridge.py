#!/usr/bin/env python3
"""Stream a PipeWire sink to AirPlay 2 speakers, in sync.

A HomePod stereo pair is not one endpoint on the wire. Apple's own senders
open a separate AirPlay 2 session to *each* member, push the full stereo
stream to both, and keep them together with a single PTP grandmaster and one
agreed start instant; each speaker picks its own side out of the stereo it
receives. This does the same thing:

    PipeWire sink monitor -> pw-record (s16le 44100 stereo)
                          -> tee -> cliairplay -> Office
                                 -> cliairplay -> Office (2)

Timing comes from `cliairplay --ptp-daemon`, which owns UDP 319/320 for the
whole host; these sessions attach to its clock with --ptp-shared. Without
that daemon each session falls back to its own NTP responder, the speakers
never slave to a common clock, and a HomePod renders silence however healthy
the session looks.

The bridge idles until something actually plays to the sink, so the speakers
stay free for phones and Macs the rest of the time.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import threading
import time
from typing import IO

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from airplay_common import browse, load_creds, log

CLIAIRPLAY = os.environ.get("CLIAIRPLAY", "cliairplay")
PW_RECORD = os.environ.get("PW_RECORD", "pw-record")
PW_DUMP = os.environ.get("PW_DUMP", "pw-dump")

RATE = 44100
CHANNELS = 2
CHUNK = 8192

# How long every member gets to connect and buffer before we give up and
# rebuild the session.
CONNECT_TIMEOUT = 30.0
# Least lead time between commanding a start and the first audible sample.
#
# This is not only a startup cost. The capture runs while we wait, so whatever
# audio is fed before the anchor queues up inside cliairplay and plays out
# ahead of everything after it — the lead becomes permanent latency, one
# second of waiting for one second of lag on every later seek. The session is
# drained immediately before the START (see _start_together), so the lead only
# has to clear the receiver's warm floor: its splice queue depth (600 ms by
# default, reported as warm_lead_ms) plus cliairplay's own 250 ms minimum warm
# lead. 1000 ms clears both with a little slack for the command to land.
START_LEAD_MS = 1000
# Two members that seat different instants play the same music that far apart —
# a fixed echo, not drift. Re-align above this much skew.
START_SKEW_TOLERANCE_MS = 5
# How long a member gets to acknowledge a START before we stop waiting.
START_ACK_TIMEOUT = 10.0
# How long a member gets to acknowledge the pre-start drain.
FLUSH_TIMEOUT = 5.0
# Attempts to land every member on one instant before giving up on the session.
START_ALIGN_ATTEMPTS = 3


def _fields(line: str) -> dict[str, str]:
    """The KEY=VALUE tail of a [STATUS] line."""
    return dict(part.split("=", 1) for part in line.split() if "=" in part)


class Member:
    """One speaker: a cliairplay process plus what it has told us so far."""

    def __init__(self, device: str, sender_name: str, iface: str | None):
        self.device = device
        self.sender_name = sender_name
        self.iface = iface
        self.proc: subprocess.Popen | None = None
        self.stdin: IO[bytes] | None = None
        self.stdout: IO[bytes] | None = None
        self.cmdpipe_fd: int | None = None
        self.cmdpipe_path: str | None = None
        self.audio_ready = threading.Event()
        self.failed = threading.Event()
        self.ready_at_unix_ms = 0
        self.timing_mode = "unknown"
        # Every START is acknowledged with the instant the receiver could
        # actually seat, which is not always the one we named.
        self.started_ack = threading.Event()
        self.started_requested_ms = 0
        self.started_at_ms = 0
        self.flushed = threading.Event()

    # -- lifecycle ---------------------------------------------------------

    def start(self, target: dict, runtime_dir: str, volume: int) -> None:
        creds = load_creds(self.device)

        self.cmdpipe_path = os.path.join(runtime_dir, f"cmd-{id(self)}")
        os.mkfifo(self.cmdpipe_path, 0o600)

        argv = [
            CLIAIRPLAY,
            "--protocol", "airplay2",
            "--port", str(target["port"]),
            "--name", self.sender_name,
            "--txt", target["txt"],
            "--samplerate", str(RATE),
            "--channels", str(CHANNELS),
            "--bitdepth", "16",
            "--volume", str(volume),
            # Take the shared grandmaster if the host daemon is up rather than
            # trying to bind 319/320 from an unprivileged session.
            "--ptp-shared",
            "--cmdpipe", self.cmdpipe_path,
        ]
        # A HomePod takes anonymous transient pairing, so nothing has to be
        # paired by hand. Stored credentials are only there for a receiver
        # that refuses it, and they win when present.
        if creds:
            argv += ["--auth", creds["auth"], "--dacp", creds["dacp"]]
        else:
            argv += ["--ap2-native"]
        if self.iface:
            argv += ["--if", self.iface, "--publish-ip", self.iface]
        argv.append(target["address"])

        proc = subprocess.Popen(
            argv,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0,
        )
        # Popen was asked for both pipes, so it created both. Hold them
        # directly: the audio path and the status reader use them on every
        # chunk and every line, and neither wants an optional in the way.
        if proc.stdin is None or proc.stdout is None:
            proc.kill()
            raise RuntimeError("subprocess pipes were not created")
        self.proc = proc
        self.stdin = proc.stdin
        self.stdout = proc.stdout

        # Opening the FIFO read-write keeps it from blocking here and from
        # signalling EOF to the child between our writes.
        self.cmdpipe_fd = os.open(self.cmdpipe_path, os.O_RDWR | os.O_NONBLOCK)

        threading.Thread(
            target=self._read_status, args=(proc.stdout,), daemon=True
        ).start()
        log(f"{self.device}: connecting to {target['address']}:{target['port']}")

    def _read_status(self, stdout: IO[bytes]) -> None:
        for raw in stdout:
            line = raw.decode("utf-8", "replace").rstrip()
            if not line:
                continue
            if "[STATUS] audio" in line:
                self.audio_ready.set()
            elif "[STATUS] clock_ready" in line:
                fields = _fields(line)
                self.timing_mode = fields.get("mode", "unknown")
                try:
                    self.ready_at_unix_ms = int(fields.get("ready_at_unix_ms", 0))
                except ValueError:
                    self.ready_at_unix_ms = 0
            elif "[STATUS] started" in line:
                fields = _fields(line)
                try:
                    self.started_requested_ms = int(
                        fields.get("requested_unix_ms", 0)
                    )
                    self.started_at_ms = int(fields.get("at_unix_ms", 0))
                except ValueError:
                    self.started_requested_ms = self.started_at_ms = 0
                log(f"{self.device}: {line}")
                self.started_ack.set()
            elif "[STATUS] flushed" in line:
                log(f"{self.device}: {line}")
                self.flushed.set()
            elif "[STATUS] error" in line or "[ERROR]" in line:
                log(f"{self.device}: {line}")
                self.failed.set()
            elif "[STATUS]" in line:
                log(f"{self.device}: {line}")
        self.failed.set()

    def command(self, *lines: str) -> None:
        if self.cmdpipe_fd is None:
            return
        try:
            os.write(self.cmdpipe_fd, ("".join(f"{l}\n" for l in lines)).encode())
        except OSError as exc:
            log(f"{self.device}: cmdpipe write failed: {exc}")

    def feed(self, data: bytes) -> bool:
        stdin = self.stdin
        if stdin is None:
            return False
        # These pipes are unbuffered, so a single write() can be short. Losing
        # the remainder would drop samples and desynchronise the pair, so keep
        # writing until the whole chunk is gone.
        view = memoryview(data)
        try:
            while view:
                written = stdin.write(view)
                if written:
                    view = view[written:]
            return True
        except (BrokenPipeError, ValueError, OSError):
            self.failed.set()
            return False

    def stop(self) -> None:
        if self.proc and self.proc.poll() is None:
            self.command("ACTION=STOP", "ACTION=DISCONNECT")
            # Closing stdin unblocks the child if it is still waiting on audio.
            if self.stdin is not None:
                try:
                    self.stdin.close()
                except (OSError, ValueError):
                    pass
            try:
                self.proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.proc.terminate()
                try:
                    self.proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.proc.kill()
        if self.cmdpipe_fd is not None:
            os.close(self.cmdpipe_fd)
            self.cmdpipe_fd = None
        if self.cmdpipe_path and os.path.exists(self.cmdpipe_path):
            os.unlink(self.cmdpipe_path)
        self.proc = None
        self.stdin = None
        self.stdout = None


def sink_is_active(sink: str) -> bool:
    """True when something is actually playing to the sink.

    PipeWire parks an idle sink in "suspended"/"idle" and only marks it
    "running" while a stream is linked and feeding it.
    """
    try:
        out = subprocess.run(
            [PW_DUMP], capture_output=True, text=True, timeout=10
        ).stdout
        for obj in json.loads(out):
            info = obj.get("info") or {}
            props = info.get("props") or {}
            if props.get("node.name") == sink:
                return info.get("state") == "running"
    except Exception as exc:  # pw-dump is best-effort; never crash the loop
        log(f"pw-dump failed: {exc}")
    return False


def sink_volume(sink: str) -> int | None:
    """The sink's fader as an AirPlay 0-100 volume, or None if unreadable."""
    try:
        out = subprocess.run(
            [PW_DUMP], capture_output=True, text=True, timeout=10
        ).stdout
        for obj in json.loads(out):
            info = obj.get("info") or {}
            if (info.get("props") or {}).get("node.name") != sink:
                continue
            return _volume_from_props(info)
    except Exception as exc:
        log(f"pw-dump failed while reading volume: {exc}")
    return None


def _volume_from_props(info: dict) -> int | None:
    """Map a sink node's fader onto AirPlay's 0-100.

    PipeWire stores channelVolumes as the *cubed* fader position, so a slider
    at 90% is 0.729 of linear amplitude. AirPlay's own 0-100 is linear in dB
    over -30..0 with 0 as mute, which is already a loudness taper — so undo the
    cube and hand the fader position across directly. Matching the two tapers
    rather than the raw gains is what makes the speaker track the slider the
    way every other AirPlay sender does.
    """
    for entry in (info.get("params") or {}).get("Props") or []:
        volumes = entry.get("channelVolumes")
        if not volumes:
            continue
        if entry.get("mute"):
            return 0
        gain = max(volumes)
        if gain <= 0:
            return 0
        return max(0, min(100, round(gain ** (1.0 / 3.0) * 100)))
    return None


def ptp_daemon_running() -> bool:
    return os.path.exists("/dev/shm/cliairplay-ptp")


class Session:
    """One synchronised playback session across every member."""

    # Said once per process, not once per reconnect attempt.
    warned_no_ptp = False

    def __init__(self, args):
        self.args = args
        self.members = [
            Member(device, args.sender_name, args.iface) for device in args.devices
        ]
        self.recorder: subprocess.Popen | None = None
        self.stop_flag = threading.Event()
        self.pump: threading.Thread | None = None
        # While set, the pump reads the capture and throws it away, so a drain
        # is not racing fresh audio back into the pipe it is emptying.
        self.draining = threading.Event()
        self.volume_mon: subprocess.Popen | None = None
        self.volume_watch: threading.Thread | None = None
        self.volume = 0

    def start(self) -> bool:
        if not ptp_daemon_running() and not Session.warned_no_ptp:
            Session.warned_no_ptp = True
            log(
                "no PTP daemon at /dev/shm/cliairplay-ptp. A HomePod refuses "
                "an NTP-timed AirPlay 2 session outright, so this will fail "
                "at SETUP. Start it:  systemctl start airplay-ptp"
            )

        # One mDNS browse for the whole group, so both members come up
        # together instead of one waiting out the other's scan.
        receivers = browse()
        missing = [m.device for m in self.members if m.device not in receivers]
        if missing:
            raise LookupError(f"not on the LAN: {', '.join(missing)}")

        # The speaker's own volume tracks the sink fader, so open at whatever
        # the fader already says rather than at a fixed level the desktop
        # knows nothing about.
        self.volume = sink_volume(self.args.sink)
        if self.volume is None:
            self.volume = self.args.volume
            log(f"could not read the sink fader; opening at volume {self.volume}")

        runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
        for member in self.members:
            member.start(receivers[member.device], runtime, self.volume)

        recorder = subprocess.Popen(
            [
                PW_RECORD,
                "--raw",
                # pw-record's --target takes a *node* name or serial, and a
                # sink's monitor is a set of ports on the sink node, not a node
                # of its own: "<sink>.monitor" never resolves, pw-record falls
                # back to the default source, and the bridge quietly ships the
                # microphone (muted, so: digital silence) to the speakers.
                # Name the sink node and ask for its monitor side explicitly.
                f"--target={self.args.sink}",
                "-P", "stream.capture.sink=true",
                "--format", "s16",
                "--rate", str(RATE),
                "--channels", str(CHANNELS),
                "--latency", "1024/44100",
                "-",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            bufsize=0,
        )
        if recorder.stdout is None:
            recorder.kill()
            raise RuntimeError("pw-record stdout pipe was not created")
        self.recorder = recorder

        self.pump = threading.Thread(
            target=self._pump_audio, args=(recorder.stdout,), daemon=True
        )
        self.pump.start()
        self._watch_volume()

        deadline = time.monotonic() + CONNECT_TIMEOUT
        for member in self.members:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not member.audio_ready.wait(timeout=remaining):
                log(f"{member.device}: did not buffer audio in time")
                return False
            if member.failed.is_set():
                return False

        return self._start_together()

    def _drain(self) -> None:
        """Throw away everything captured while the session was coming up.

        Getting here takes seconds — mDNS, two RTSP handshakes, a PTP servo —
        and the capture has been running throughout. All of it is sitting in
        cliairplay's ring, and none of it is stale from the receiver's point of
        view: it would simply play, in order, pushing every later sample that
        much further behind the desktop. Left alone this measured ~6.9 s of
        standing latency. FLUSH resets the ring and drains the pipe, so the
        first sample the speakers play is one captured just before the anchor.
        """
        self.draining.set()
        try:
            for member in self.members:
                member.flushed.clear()
                member.command("ACTION=FLUSH")
            deadline = time.monotonic() + FLUSH_TIMEOUT
            for member in self.members:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not member.flushed.wait(timeout=remaining):
                    log(f"{member.device}: no flush ack; starting anyway")
        finally:
            self.draining.clear()

    def _start_together(self) -> bool:
        """Land every member on one audible instant.

        Naming an instant is a request, not a guarantee: a receiver whose clock
        exchange has not been verified yet corrects the anchor forward to the
        earliest instant it can seat and reports that in its START ack. Two
        members that correct differently play the same music a fixed distance
        apart — an echo across the pair that never closes, because nothing here
        drifts. So read every ack back, and when they disagree re-issue the
        START at the latest instant anyone claimed, which every member can by
        then seat. Upstream names this the caller's job.
        """
        self._drain()
        for attempt in range(1, START_ALIGN_ATTEMPTS + 1):
            # Members on the shared PTP clock report when their servo will be
            # settled; start no earlier than the latest of those.
            start_ms = int(time.time() * 1000) + START_LEAD_MS
            for member in self.members:
                if member.timing_mode == "ptp" and member.ready_at_unix_ms:
                    start_ms = max(start_ms, member.ready_at_unix_ms)

            log(f"starting all members at unix_ms={start_ms} (attempt {attempt})")
            for member in self.members:
                member.started_ack.clear()
                member.command(f"START_UNIX_MS={start_ms}", "ACTION=START")

            deadline = time.monotonic() + START_ACK_TIMEOUT
            for member in self.members:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not member.started_ack.wait(timeout=remaining):
                    log(f"{member.device}: did not acknowledge START in time")
                    return False
                if member.failed.is_set():
                    return False

            seated = [member.started_at_ms for member in self.members]
            skew = max(seated) - min(seated)
            if skew <= START_SKEW_TOLERANCE_MS:
                log(f"all members seated within {skew} ms")
                return True

            log(
                f"start skew {skew} ms across the pair "
                f"({', '.join(f'{m.device}={m.started_at_ms}' for m in self.members)})"
                " — re-aligning"
            )
            # Wait out the instants already committed, so the next attempt names
            # a time that is still ahead of every member rather than one they
            # have to correct forward again.
            settle = max(seated) / 1000.0 - time.time()
            if settle > 0:
                time.sleep(min(settle, START_ACK_TIMEOUT))

        log("gave up aligning the pair; rebuilding the session")
        return False

    def _watch_volume(self) -> None:
        """Send fader moves straight to the speakers, ahead of the audio.

        The capture carries PCM at unity, so a fader move has to reach the
        speakers as a volume *command* rather than as quieter samples. That is
        the difference between reacting now and reacting once the audio that
        was already in flight has drained: an AirPlay volume is an RTSP
        SET_PARAMETER on the control channel, which overtakes the whole
        pipeline instead of queueing behind it.
        """
        try:
            mon = subprocess.Popen(
                [PW_DUMP, "-m", "-N"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1,
            )
        except OSError as exc:
            log(f"could not watch the sink fader, volume will not track: {exc}")
            return
        if mon.stdout is None:
            mon.kill()
            return
        self.volume_mon = mon
        self.volume_watch = threading.Thread(
            target=self._pump_volume, args=(mon.stdout,), daemon=True
        )
        self.volume_watch.start()

    def _pump_volume(self, source: IO[str]) -> None:
        # pw-dump -m emits a whole JSON array per change, pretty-printed across
        # many lines, so accumulate until one parses and then drop it.
        decoder = json.JSONDecoder()
        buf = ""
        while not self.stop_flag.is_set():
            line = source.readline()
            if not line:
                break
            buf += line
            while buf:
                stripped = buf.lstrip()
                if not stripped:
                    buf = ""
                    break
                try:
                    objs, end = decoder.raw_decode(stripped)
                except ValueError:
                    break  # not a whole array yet
                buf = stripped[end:]
                self._apply_volume(objs)

    def _apply_volume(self, objs) -> None:
        if not isinstance(objs, list):
            return
        for obj in objs:
            info = obj.get("info") or {}
            if (info.get("props") or {}).get("node.name") != self.args.sink:
                continue
            volume = _volume_from_props(info)
            if volume is None or volume == self.volume:
                continue
            self.volume = volume
            log(f"fader moved: volume {volume}")
            for member in self.members:
                member.command(f"VOLUME={volume}")

    def _pump_audio(self, source: IO[bytes]) -> None:
        """Feed one capture to every member, byte for byte."""
        while not self.stop_flag.is_set():
            data = source.read(CHUNK)
            if not data:
                break
            if self.draining.is_set():
                continue
            for member in self.members:
                member.feed(data)
        self.stop_flag.set()

    def healthy(self) -> bool:
        if self.stop_flag.is_set():
            return False
        if self.recorder and self.recorder.poll() is not None:
            return False
        return not any(member.failed.is_set() for member in self.members)

    def stop(self) -> None:
        self.stop_flag.set()
        if self.recorder and self.recorder.poll() is None:
            self.recorder.terminate()
            try:
                self.recorder.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.recorder.kill()
        self.recorder = None
        if self.volume_mon and self.volume_mon.poll() is None:
            self.volume_mon.terminate()
            try:
                self.volume_mon.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.volume_mon.kill()
        self.volume_mon = None
        for member in self.members:
            member.stop()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--sink", required=True, help="PipeWire sink node.name to bridge")
    ap.add_argument(
        "--device",
        dest="devices",
        action="append",
        required=True,
        help="Home name of a speaker; repeat for every member of a pair",
    )
    ap.add_argument("--sender-name", default="liminal")
    ap.add_argument("--volume", type=int, default=50)
    ap.add_argument("--iface", help="local IPv4 to bind and advertise (multi-homed hosts)")
    ap.add_argument(
        "--idle-timeout",
        type=float,
        default=30.0,
        help="seconds of silence before releasing the speakers",
    )
    args = ap.parse_args()

    running = threading.Event()
    running.set()

    def handle_signal(_sig, _frm):
        running.clear()

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    session: Session | None = None
    idle_since: float | None = None
    last_error: str | None = None
    log(f"watching sink {args.sink} for {', '.join(args.devices)}")

    while running.is_set():
        active = sink_is_active(args.sink)

        if active and session is None:
            try:
                session = Session(args)
                if session.start():
                    last_error = None
                else:
                    session.stop()
                    session = None
                    time.sleep(5)
            except (LookupError, OSError, ValueError) as exc:
                # The sink stays selected while a speaker is unpaired or off
                # the LAN, so this retries forever; say it once per cause.
                if str(exc) != last_error:
                    last_error = str(exc)
                    log(f"cannot start session: {exc}")
                if session:
                    session.stop()
                session = None
                time.sleep(10)
            idle_since = None

        elif session is not None:
            if not session.healthy():
                log("session ended unexpectedly; tearing down")
                session.stop()
                session = None
                time.sleep(3)
            elif active:
                idle_since = None
            else:
                idle_since = idle_since or time.monotonic()
                if time.monotonic() - idle_since >= args.idle_timeout:
                    log("idle; releasing the speakers")
                    session.stop()
                    session = None
                    idle_since = None

        time.sleep(1)

    if session:
        session.stop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
