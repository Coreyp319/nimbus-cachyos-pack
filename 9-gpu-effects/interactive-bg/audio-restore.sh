#!/usr/bin/env bash
# Stop + remove the Nimbus Aurora music-reactivity bridge. Pass --purge to also
# delete the installed daemon script. Run as your normal user.
set -uo pipefail
PURGE="${1:-}"
DAEMON_DIR="$HOME/.local/share/nimbus-aurora"
UNIT="nimbus-aurora-audio.service"
UNIT_DEST="$HOME/.config/systemd/user/$UNIT"
RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; }

systemctl --user disable --now "$UNIT" 2>/dev/null && ok "music bridge stopped + disabled" || \
  echo "    music bridge wasn't running."
rm -f "$RUNTIME/nimbus-aurora/audio.json"

if [ "$PURGE" = "--purge" ]; then
  rm -f "$UNIT_DEST" "$DAEMON_DIR/aurora-audio-bridge.py"
  systemctl --user daemon-reload 2>/dev/null || true
  ok "removed audio bridge unit + daemon script"
else
  rm -f "$UNIT_DEST"; systemctl --user daemon-reload 2>/dev/null || true
  echo "    Left the daemon script in place (run with --purge to remove it)."
fi
