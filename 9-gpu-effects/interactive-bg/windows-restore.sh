#!/usr/bin/env bash
# Revert the WhiteSur Aurora window-reactivity bridge: stop + disable the daemon,
# unload + disable the KWin script, drop the state file. Pass --purge to also
# delete the installed daemon, user unit and KWin script. Run as your normal user.
set -uo pipefail
PURGE="${1:-}"
SCRIPT_ID="whitesur-aurora-windows"
KWIN_DEST="$HOME/.local/share/kwin/scripts/$SCRIPT_ID"
DAEMON_DIR="$HOME/.local/share/whitesur-aurora"
UNIT="whitesur-aurora-bridge.service"
UNIT_DEST="$HOME/.config/systemd/user/$UNIT"
STATE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/whitesur-aurora/windows.json"

ok(){   printf '  \033[32m✓\033[0m %s\n' "$1"; }

# 1. KWin script off (config + live unload)
kwriteconfig6 --file kwinrc --group Plugins --key "${SCRIPT_ID}Enabled" false 2>/dev/null || true
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$SCRIPT_ID" >/dev/null 2>&1 || true
ok "KWin script disabled + unloaded"

# 2. daemon off
systemctl --user disable --now "$UNIT" >/dev/null 2>&1 || true
ok "bridge daemon stopped + disabled"

# 3. state file
rm -f "$STATE" 2>/dev/null || true

if [ "$PURGE" = "--purge" ]; then
  rm -rf "$KWIN_DEST" "$DAEMON_DIR" "$UNIT_DEST"
  systemctl --user daemon-reload 2>/dev/null || true
  ok "purged KWin script, daemon + user unit"
else
  echo "    Left files installed (run with --purge to remove them)."
fi
