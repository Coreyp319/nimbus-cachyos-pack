#!/usr/bin/env bash
# Revert Layer 7 — restore Plasma's built-in notifications. Surgical + idempotent.
# --purge also deletes the swaync config and removes the package.
set -uo pipefail
PURGE="${1:-}"

CFG="$HOME/.config/swaync"
DBUS_DIR="$HOME/.local/share/dbus-1/services"
TRAY="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

echo "1/6 Stopping swaync + the CSS watcher…"
systemctl --user disable --now swaync.service swaync-apply-scheme.path 2>/dev/null || true
systemctl --user stop swaync-apply-scheme.service 2>/dev/null || true

echo "2/6 Removing the D-Bus shadow (returns the name to Plasma)…"
rm -f "$DBUS_DIR/org.freedesktop.Notifications.service"

echo "3/6 Re-enabling the Plasma tray Notifications entry…"
hdr=$(awk '/^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/{cur=$0}
           /^plugin=org\.kde\.plasma\.systemtray$/{print cur; exit}' "$TRAY" 2>/dev/null || true)
ids=$(printf '%s\n' "$hdr" | grep -oE '[0-9]+' || true)
CID=$(printf '%s\n' "$ids" | sed -n 1p); AID=$(printf '%s\n' "$ids" | sed -n 2p)
if [ -n "${CID:-}" ] && [ -n "${AID:-}" ]; then
  ei=$(kreadconfig6 --file "$TRAY" --group Containments --group "$CID" --group Applets \
        --group "$AID" --group General --key extraItems 2>/dev/null || true)
  if ! printf ',%s,' "$ei" | grep -q ',org.kde.plasma.notifications,'; then
    new="${ei:+$ei,}org.kde.plasma.notifications"
    kwriteconfig6 --file "$TRAY" --group Containments --group "$CID" --group Applets \
      --group "$AID" --group General --key extraItems "$new"
  fi
fi

echo "4/6 Removing the Meta+N shortcut + launcher + scheme helper…"
kwriteconfig6 --file kglobalshortcutsrc --group "swaync-toggle.desktop" --key "_launch" --delete 2>/dev/null || true
rm -f "$HOME/.local/share/applications/swaync-toggle.desktop"
rm -f "$HOME/.local/bin/swaync-apply-scheme.sh"
rm -f "$HOME/.config/systemd/user/swaync-apply-scheme.service" \
      "$HOME/.config/systemd/user/swaync-apply-scheme.path"
systemctl --user daemon-reload 2>/dev/null || true
kbuildsycoca6 >/dev/null 2>&1 || true

echo "5/6 Restoring swaync config…"
if [ -f "$CFG/config.json.orig" ]; then
  mv -f "$CFG/config.json.orig" "$CFG/config.json"
  echo "    restored your pre-existing swaync config."
fi

echo "6/6 Restarting plasmashell to reclaim the notification server…"
kquitapp6 plasmashell >/dev/null 2>&1 || true
(kstart plasmashell >/dev/null 2>&1 &) 2>/dev/null || (setsid plasmashell >/dev/null 2>&1 &)

if [ "$PURGE" = "--purge" ]; then
  rm -rf "$CFG"
  sudo pacman -Rns --noconfirm swaync 2>/dev/null || true
  echo "    Purged swaync config + package."
else
  echo "    Left swaync installed (run with --purge to remove config + package)."
fi

echo "Done. LOG OUT / back in to fully restore Plasma's native notifications."
