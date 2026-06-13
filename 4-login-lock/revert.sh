#!/usr/bin/env bash
# Revert layer 4 — restore stock Breeze login + lock screen. Surgical.
set -eu
THEME_DIR=/usr/share/sddm/themes/breeze

echo "1/2 Lock screen → stock (removing WhiteSur theme + Big Sur wallpaper)…"
kwriteconfig6 --file kscreenlockerrc --group Greeter --key Theme --delete 2>/dev/null || true
kwriteconfig6 --file kscreenlockerrc \
  --group Greeter --group Wallpaper --group org.kde.image --group General \
  --key Image --delete 2>/dev/null || true

echo "2/2 SDDM → stock breeze (removing override; sudo may prompt)…"
sudo rm -f "$THEME_DIR/theme.conf.user" "$THEME_DIR/bigsur.jpg" /etc/sddm.conf.d/10-nimbus.conf

echo "Reverted. Login + lock screens are back to stock Breeze."
