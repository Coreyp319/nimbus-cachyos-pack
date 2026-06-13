#!/usr/bin/env bash
# Layer 7 — Apple-style notifications (SwayNotificationCenter).
#
# Replaces Plasma's built-in notifications (a compiled C++ applet we can't
# restyle) with swaync — a GTK4 layer-shell daemon that's fully CSS-themeable.
# You get a rounded, translucent/frosted toast in the top-right with ample
# whitespace, styled action buttons + inline reply, and a notification-center
# panel with a Do-Not-Disturb toggle (Meta+N).
#
#   NOTE on blur: KWin does not blur layer-shell surfaces, so the "frost" is
#   translucency (a soft rgba card over the wallpaper), not compositor blur.
#
# User-level except the package install (sudo, prompts once). Reversible via
# revert.sh. Light/dark rides the existing Meta+Ctrl+T toggle automatically.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" -eq 0 ] && { echo "Run as your normal user, not root."; exit 1; }

ALL=0; case "${1:-}" in -y|--yes) ALL=1 ;; -h|--help)
  echo "Usage: bash install.sh [-y]"; exit 0 ;; esac

ok(){   printf '  \033[32m✓\033[0m %s\n' "$1"; }
msg(){  printf '\n\033[1m:: %s\033[0m\n' "$1"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$1"; }

CFG="$HOME/.config/swaync"
DBUS_DIR="$HOME/.local/share/dbus-1/services"
TRAY="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

# --- 1. package ------------------------------------------------------------
msg "Installing swaync (sudo)…"
sudo pacman -S --needed --noconfirm swaync || { warn "swaync install failed — aborting"; exit 1; }

# --- 2. config + CSS + scheme-apply helper ---------------------------------
msg "Deploying swaync config + Apple-frosted CSS…"
mkdir -p "$CFG" "$HOME/.local/bin"
[ -f "$CFG/config.json" ] && [ ! -f "$CFG/config.json.orig" ] && cp "$CFG/config.json" "$CFG/config.json.orig"
install -m644 "$HERE/config.json"     "$CFG/config.json"
install -m644 "$HERE/style-light.css" "$CFG/style-light.css"
install -m644 "$HERE/style-dark.css"  "$CFG/style-dark.css"
install -m755 "$HERE/bin/swaync-apply-scheme.sh" "$HOME/.local/bin/swaync-apply-scheme.sh"
"$HOME/.local/bin/swaync-apply-scheme.sh" || true   # writes style.css for the active scheme
ok "config + light/dark CSS in $CFG"

# --- 3. hand org.freedesktop.Notifications to swaync -----------------------
# (a) Decisive: a user-level D-Bus shadow service. The user data dir wins over
#     /usr/share, so this overrides Plasma's org.kde.plasma.Notifications.service
#     for the activatable freedesktop name. (Proven method; needs a relogin.)
msg "Pointing the notification D-Bus name at swaync…"
mkdir -p "$DBUS_DIR"
install -m644 "$HERE/dbus/org.freedesktop.Notifications.service" \
  "$DBUS_DIR/org.freedesktop.Notifications.service"
ok "D-Bus shadow service installed"

# (b) Belt-and-suspenders: disable the system-tray Notifications applet so
#     plasmashell stops registering its own server. "Disabled" == removed from
#     the tray's extraItems catalog. IDs discovered at runtime (portable).
hdr=$(awk '/^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/{cur=$0}
           /^plugin=org\.kde\.plasma\.systemtray$/{print cur; exit}' "$TRAY" 2>/dev/null || true)
ids=$(printf '%s\n' "$hdr" | grep -oE '[0-9]+' || true)
CID=$(printf '%s\n' "$ids" | sed -n 1p); AID=$(printf '%s\n' "$ids" | sed -n 2p)
if [ -n "${CID:-}" ] && [ -n "${AID:-}" ]; then
  ei=$(kreadconfig6 --file "$TRAY" --group Containments --group "$CID" --group Applets \
        --group "$AID" --group General --key extraItems 2>/dev/null || true)
  if printf ',%s,' "$ei" | grep -q ',org.kde.plasma.notifications,'; then
    new=$(printf '%s' "$ei" | tr ',' '\n' | grep -vx 'org.kde.plasma.notifications' | paste -sd ',' -)
    kwriteconfig6 --file "$TRAY" --group Containments --group "$CID" --group Applets \
      --group "$AID" --group General --key extraItems "$new"
    ok "Plasma tray Notifications entry disabled"
  else
    ok "Plasma tray Notifications entry already disabled"
  fi
else
  warn "couldn't locate the system-tray applet — relying on the D-Bus shadow + relogin"
fi

# --- 4. light/dark watcher (mirrors Layer 2's icon watcher) ----------------
msg "Installing the light/dark CSS watcher…"
mkdir -p "$HOME/.config/systemd/user"
install -m644 "$HERE/systemd/swaync-apply-scheme.service" "$HOME/.config/systemd/user/swaync-apply-scheme.service"
install -m644 "$HERE/systemd/swaync-apply-scheme.path"    "$HOME/.config/systemd/user/swaync-apply-scheme.path"
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now swaync-apply-scheme.path 2>/dev/null || true
ok "swaync repaints on light↔dark (rides your Meta+Ctrl+T toggle)"

# --- 5. notification-center shortcut (Meta+N) ------------------------------
msg "Binding the notification center to Meta+N…"
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/swaync-toggle.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Notification Center
Comment=Toggle the macOS-style notification center
Exec=swaync-client -t -sw
Icon=preferences-desktop-notification
Terminal=false
Categories=Utility;
EOF
kwriteconfig6 --file kglobalshortcutsrc --group "swaync-toggle.desktop" --key "_launch" \
  "Meta+N,none,Notification Center"
kbuildsycoca6 >/dev/null 2>&1 || true
ok "Meta+N toggles the notification center (after next login)"

# --- 6. start swaync + live handoff ----------------------------------------
# Order matters: swaync.service is Type=dbus with BusName=org.freedesktop.Notifications,
# so it exits immediately if the name is still owned. Release it from plasmashell
# FIRST (restart it now that the tray applet is disabled, so it comes up without
# the notification server), let the name drop, THEN start swaync.
msg "Releasing the notification bus from Plasma…"
systemctl --user enable swaync.service >/dev/null 2>&1 || true   # enable only (no start yet)
kquitapp6 plasmashell >/dev/null 2>&1 || true
(kstart plasmashell >/dev/null 2>&1 &) 2>/dev/null || (setsid plasmashell >/dev/null 2>&1 &)
sleep 3   # give plasmashell time to quit + relaunch and drop org.freedesktop.Notifications

msg "Starting swaync…"
systemctl --user reset-failed swaync.service >/dev/null 2>&1 || true   # clear any prior start-limit
systemctl --user start swaync.service 2>/dev/null || true
sleep 1
if systemctl --user is-active --quiet swaync.service; then
  swaync-client --reload-config -sw >/dev/null 2>&1 || true
  swaync-client --reload-css    -sw >/dev/null 2>&1 || true
  ok "swaync running and owns notifications"
else
  warn "swaync didn't claim the bus yet — log out / back in and it will start cleanly"
  systemctl --user reset-failed swaync.service >/dev/null 2>&1 || true
fi

# --- 7. demo ---------------------------------------------------------------
if [ "$ALL" != 1 ]; then
  printf '\n  Send a quick demo notification now? [Y/n] '
  read -r r </dev/tty 2>/dev/null || r=n
  case "$r" in [nN]*) : ;; *) bash "$HERE/demo/swaync-demo.sh" || true ;; esac
fi

cat <<'DONE'

  ────────────────────────────────────────────────────────────
  ✅  Layer 7 done — Apple-style notifications via swaync.
      • LOG OUT / back in to guarantee swaync owns notifications
        (and to activate the Meta+N shortcut).
      • Toggle the center:  Meta+N   (or: swaync-client -t -sw)
      • Do Not Disturb lives at the top of the center.
      • Light/dark follows your Meta+Ctrl+T toggle automatically.
      Revert:  ./revert.sh   (--purge also removes config + package)
  ────────────────────────────────────────────────────────────
DONE
