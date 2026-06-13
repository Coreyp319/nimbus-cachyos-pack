#!/usr/bin/env python3
"""Nimbus Aurora — music-reactivity bridge.

Taps the default sink's *monitor* with `pw-cat`, runs an FFT, and writes
bass/mid/treble/level/beat (each 0..1, AGC-normalised) to
$XDG_RUNTIME_DIR/nimbus-aurora/audio.json at ~60 Hz. The wallpaper polls that
file (same pattern as the window bridge) and feeds the shader.

It listens to the user's OWN audio output monitor — no microphone, no window
content, no D-Bus. Follows the default sink if it changes; emits zeros when idle.

Deps: pw-cat (pipewire) + numpy. Run as a systemd --user service.
"""
import os
import sys
import json
import time
import tempfile
import threading
import collections
import subprocess

import numpy as np

RATE   = 48000
CHUNK  = 1024                 # samples per read (~21 ms)
WIN    = 2048                 # FFT window
OUT_HZ = 60

RUNTIME  = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
OUT_DIR  = os.path.join(RUNTIME, "nimbus-aurora")
OUT_FILE = os.path.join(OUT_DIR, "audio.json")


def default_monitor():
    try:
        sink = subprocess.check_output(["pactl", "get-default-sink"], text=True).strip()
        return (sink + ".monitor") if sink else None
    except Exception:
        return None


class Capture(threading.Thread):
    """Spawn pw-cat on the current default monitor into a ring buffer; restart it
    if the default sink changes or the process dies. Runs off the main loop so a
    blocked read (sink suspended) never stalls the writer."""
    def __init__(self):
        super().__init__(daemon=True)
        self.buf = collections.deque(np.zeros(WIN, dtype=np.float32), maxlen=WIN)
        self.lock = threading.Lock()
        self.last_data = 0.0

    def run(self):
        cur, proc, pending = None, None, b""
        while True:
            mon = default_monitor()
            if mon != cur or proc is None or proc.poll() is not None:
                if proc:
                    try: proc.kill()
                    except Exception: pass
                cur = mon
                if not mon:
                    time.sleep(0.5); continue
                proc = subprocess.Popen(
                    ["pw-cat", "--record", "--target", mon, "--format", "s16",
                     "--rate", str(RATE), "--channels", "1", "-"],
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
                pending = proc.stdout.read(4)          # peek: skip a WAV header if present
                if pending == b"RIFF":
                    proc.stdout.read(40); pending = b""
            try:
                raw = proc.stdout.read(CHUNK * 2)
            except Exception:
                raw = b""
            if not raw:
                time.sleep(0.05); continue
            if pending:
                raw, pending = pending + raw, b""
            raw = raw[:len(raw) // 2 * 2]              # whole int16 frames only
            s = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
            with self.lock:
                self.buf.extend(s)
                self.last_data = time.monotonic()

    def snapshot(self):
        with self.lock:
            return np.asarray(self.buf, dtype=np.float32), self.last_data


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    cap = Capture(); cap.start()

    freqs = np.fft.rfftfreq(WIN, 1.0 / RATE)
    window = np.hanning(WIN).astype(np.float32)
    bmask = (freqs >= 20)   & (freqs < 250)
    mmask = (freqs >= 250)  & (freqs < 2000)
    tmask = (freqs >= 2000) & (freqs < 16000)

    peaks = {"bass": 1e-3, "mid": 1e-3, "treble": 1e-3, "level": 1e-3}
    flux_avg = 1e-3
    beat = 0.0
    period = 1.0 / OUT_HZ

    def norm(name, v):                                 # AGC: 0..1 against a decaying peak
        peaks[name] = max(v, peaks[name] * 0.999)
        return float(np.clip(v / (peaks[name] + 1e-9), 0.0, 1.0))

    while True:
        t0 = time.monotonic()
        sig, last = cap.snapshot()
        if (time.monotonic() - last) > 0.4 or sig.size < WIN:
            bass = mid = treble = level = 0.0
        else:
            sp = np.abs(np.fft.rfft(sig * window))
            bass   = float(sp[bmask].mean())
            mid    = float(sp[mmask].mean())
            treble = float(sp[tmask].mean())
            level  = float(np.sqrt(np.mean(sig * sig)))

        nb, nm, nt, nl = norm("bass", bass), norm("mid", mid), norm("treble", treble), norm("level", level)

        flux = bass + mid                              # onset detection on low+mid energy
        flux_avg = flux_avg * 0.97 + flux * 0.03
        if flux > flux_avg * 1.5 and nl > 0.15:
            beat = 1.0
        beat *= 0.82                                   # fast decay -> a ripple, not a hold

        out = {"bass": round(nb, 3), "mid": round(nm, 3), "treble": round(nt, 3),
               "level": round(nl, 3), "beat": round(beat, 3)}
        try:
            fd, tmp = tempfile.mkstemp(dir=OUT_DIR, prefix=".audio-", suffix=".json")
            with os.fdopen(fd, "w") as f:
                json.dump(out, f)
            os.replace(tmp, OUT_FILE)                   # atomic: no half-written reads
        except Exception as exc:
            sys.stderr.write("aurora-audio: write failed: %s\n" % exc)

        dt = period - (time.monotonic() - t0)
        if dt > 0:
            time.sleep(dt)


if __name__ == "__main__":
    main()
