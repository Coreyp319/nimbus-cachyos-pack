#!/usr/bin/env bash
# Install + activate the Nimbus Aurora *window-reactivity* bridge:
#   1. the KWin script  (sees live window geometry, pushes it over D-Bus)
#   2. the bridge daemon (D-Bus name org.nimbus.Aurora → state file)  as a
#      systemd --user service
# The wallpaper consumer + shader ship inside the plugin (apply.sh). Opt-in;
# only useful once the aurora is the active wallpaper. Reversible: windows-restore.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_ID="nimbus-aurora-windows"
KWIN_DEST="$HOME/.local/share/kwin/scripts/$SCRIPT_ID"
DAEMON_DIR="$HOME/.local/share/nimbus-aurora"
UNIT="nimbus-aurora-bridge.service"
UNIT_DEST="$HOME/.config/systemd/user/$UNIT"

ok(){   printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$1"; }

command -v qdbus6 >/dev/null 2>&1 || { warn "qdbus6 not found — is this a Plasma 6 session?"; exit 1; }
python3 -c "import dbus, gi" 2>/dev/null || \
  warn "python3 dbus/gi missing — install python-dbus python-gobject, then re-run."

# 1. bridge daemon + user service ------------------------------------------------
mkdir -p "$DAEMON_DIR"
cp "$HERE/aurora-bridge.py" "$DAEMON_DIR/"
chmod +x "$DAEMON_DIR/aurora-bridge.py"
mkdir -p "$(dirname "$UNIT_DEST")"
cp "$HERE/$UNIT" "$UNIT_DEST"
systemctl --user daemon-reload 2>/dev/null || true
if systemctl --user enable --now "$UNIT" 2>/dev/null; then
  ok "bridge daemon installed + started ($UNIT)"
else
  warn "could not enable the user service — start it by hand: systemctl --user enable --now $UNIT"
fi

# 2. KWin script -----------------------------------------------------------------
rm -rf "$KWIN_DEST"; mkdir -p "$KWIN_DEST"
cp -r "$HERE/kwin-script/metadata.json" "$HERE/kwin-script/contents" "$KWIN_DEST/"
kwriteconfig6 --file kwinrc --group Plugins --key "${SCRIPT_ID}Enabled" true
ok "KWin script installed → $KWIN_DEST"

# Load it live. KWin scripts ignore /KWin reconfigure; drive them via /Scripting.
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$SCRIPT_ID" >/dev/null 2>&1 || true
if qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript \
     "$KWIN_DEST/contents/code/main.js" "$SCRIPT_ID" >/dev/null 2>&1 \
   && qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1; then
  ok "KWin script loaded live"
else
  warn "couldn't load the KWin script live — it activates on next login (or toggle it"
  warn "in System Settings → Window Management → KWin Scripts)."
fi

echo "    Drag a window — the aurora should bend + glow around it. Tune the response"
echo "    with 'React to windows' in System Settings → Wallpaper → Configure."
