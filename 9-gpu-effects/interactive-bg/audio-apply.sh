#!/usr/bin/env bash
# Install + start the Nimbus Aurora *music-reactivity* bridge: a systemd --user
# service that taps the default sink's monitor (ffmpeg), FFTs it (numpy), and
# writes bass/mid/treble/level/beat to the runtime state file the wallpaper polls.
# The wallpaper consumer + shader ship inside the plugin (apply.sh). Opt-in; only
# useful once the aurora is the active wallpaper. Reversible: audio-restore.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DAEMON_DIR="$HOME/.local/share/nimbus-aurora"
UNIT="nimbus-aurora-audio.service"
UNIT_DEST="$HOME/.config/systemd/user/$UNIT"

ok(){   printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$1"; }

# ffmpeg (not pw-cat) does the capture — its buffering survives the FFT-induced read
# stalls that make pw-cat's real-time capture desync to permanent silence.
command -v ffmpeg >/dev/null 2>&1 || warn "ffmpeg not found — install 'ffmpeg' (the capture backend), then re-run."
python3 -c "import numpy" 2>/dev/null || warn "python numpy missing — install 'python-numpy', then re-run."

mkdir -p "$DAEMON_DIR"
cp "$HERE/aurora-audio-bridge.py" "$DAEMON_DIR/"
chmod +x "$DAEMON_DIR/aurora-audio-bridge.py"
mkdir -p "$(dirname "$UNIT_DEST")"
cp "$HERE/$UNIT" "$UNIT_DEST"
systemctl --user daemon-reload 2>/dev/null || true
if systemctl --user enable --now "$UNIT" 2>/dev/null; then
  ok "music bridge installed + started ($UNIT)"
else
  warn "could not enable the user service — start it by hand: systemctl --user enable --now $UNIT"
fi
echo "    Play something — the aurora should pulse with the beat. Tune the response"
echo "    with 'React to music' in System Settings → Wallpaper → Configure."
