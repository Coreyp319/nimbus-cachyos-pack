#!/usr/bin/env python3
"""Nimbus Aurora — music-reactivity bridge.

Captures the default sink's *monitor*, runs an FFT, and writes
bass/mid/treble/level/beat (each 0..1, AGC-normalised) to
$XDG_RUNTIME_DIR/nimbus-aurora/audio.json at ~30 Hz. The wallpaper polls that
file (same pattern as the window bridge) and feeds the shader.

It listens to the user's OWN audio output monitor — no microphone, no window
content, no D-Bus. Follows the default sink if it changes; emits ~0 when idle.

Capture is via **ffmpeg** (`-f pulse`), NOT pw-cat: pw-cat's real-time capture
desyncs to permanent silence the instant the Python reader is briefly delayed by
the FFT/JSON work (a PipeWire xrun it never recovers from). ffmpeg buffers
internally and tolerates that, so the values keep flowing. (pw-cat works only for
a pure read loop with no processing — useless here.)

Deps: ffmpeg + numpy + PipeWire's PulseAudio compat. Run as a systemd --user service.
"""
import os
import sys
import json
import time
import tempfile
import subprocess

import numpy as np

RATE   = 48000
WIN    = 2048                 # FFT window
OUT_HZ = 30

RUNTIME  = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
OUT_DIR  = os.path.join(RUNTIME, "nimbus-aurora")
OUT_FILE = os.path.join(OUT_DIR, "audio.json")


def default_monitor():
    try:
        sink = subprocess.check_output(["pactl", "get-default-sink"], text=True).strip()
        return (sink + ".monitor") if sink else None
    except Exception:
        return None


def spawn(mon):
    # ffmpeg reads the monitor via the PulseAudio compat layer and writes raw
    # mono s16 to stdout. Its internal buffering is what makes this robust where
    # pw-cat is not.
    return subprocess.Popen(
        ["ffmpeg", "-loglevel", "quiet", "-f", "pulse", "-i", mon,
         "-ac", "1", "-ar", str(RATE), "-f", "s16le", "-"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

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

    ring = np.zeros(WIN, dtype=np.float32)
    mon = default_monitor()
    proc = spawn(mon) if mon else None
    last_write = 0.0
    last_check = time.monotonic()

    while True:
        if proc is None:                               # no sink yet / ffmpeg gone
            time.sleep(0.5)
            mon = default_monitor()
            proc = spawn(mon) if mon else None
            continue

        # follow the default sink if it changes (cheap, throttled — ffmpeg buffers
        # through the brief pactl call)
        now = time.monotonic()
        if now - last_check > 3.0:
            last_check = now
            m = default_monitor()
            if m and m != mon:
                try: proc.kill(); proc.wait(timeout=0.5)
                except Exception: pass
                mon = m
                proc = spawn(mon)
                ring = np.zeros(WIN, dtype=np.float32)
                continue

        raw = proc.stdout.read(WIN * 2)                # blocking; ffmpeg paces us
        if not raw:                                    # ffmpeg died -> respawn
            try: proc.kill()
            except Exception: pass
            proc = None
            continue

        s = np.frombuffer(raw[:len(raw) // 2 * 2], dtype=np.int16).astype(np.float32) / 32768.0
        n = s.size
        if n >= WIN:
            ring = s[-WIN:].copy()
        else:
            ring = np.roll(ring, -n)
            ring[-n:] = s

        now = time.monotonic()
        if now - last_write < period:                  # keep reading; emit at OUT_HZ
            continue
        last_write = now

        sp = np.abs(np.fft.rfft(ring * window))
        bass   = float(sp[bmask].mean())
        mid    = float(sp[mmask].mean())
        treble = float(sp[tmask].mean())
        level  = float(np.sqrt(np.mean(ring * ring)))

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


if __name__ == "__main__":
    main()
