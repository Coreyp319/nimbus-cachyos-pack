#!/usr/bin/env bash
# Layer 4 — Login (SDDM) + Lock screen: Big Sur continuity.
#
# Brings the two stock-Breeze surfaces into the WhiteSur language by giving them
# the same Big Sur wallpaper as the desktop, so login → lock → desktop read as
# one environment.
#
#   • Lock screen  — user-level (no sudo): WhiteSur color scheme + Big Sur image.
#   • SDDM login   — system-level: overlays the breeze SDDM theme's background via
#                    a non-destructive theme.conf.user (sudo prompts once). The
#                    shipped theme.conf is left untouched.
#
# Run as your normal user: bash 4-login-lock/install.sh
# Reversible via revert.sh.
set -euo pipefail

WALL="$HOME/.local/share/wallpapers/WhiteSur-light/contents/images/3840x2160.jpg"
THEME_DIR=/usr/share/sddm/themes/breeze

if [ ! -f "$WALL" ]; then
  echo "!! Big Sur wallpaper not found at $WALL"
  echo "   Install layer 1 (the base pack) first, then re-run."
  exit 1
fi

# --- Lock screen (user) ---
echo ":: Lock screen → WhiteSur + Big Sur wallpaper…"
kwriteconfig6 --file kscreenlockerrc --group Greeter --key Theme com.github.vinceliuice.WhiteSur
kwriteconfig6 --file kscreenlockerrc \
  --group Greeter --group Wallpaper --group org.kde.image --group General \
  --key Image "$WALL"

# --- SDDM login (system) ---
echo ":: SDDM login → Big Sur background (sudo may prompt)…"
sudo install -Dm644 "$WALL" "$THEME_DIR/bigsur.jpg"
sudo tee "$THEME_DIR/theme.conf.user" >/dev/null <<CONF
[General]
type=image
background=$THEME_DIR/bigsur.jpg
CONF
sudo mkdir -p /etc/sddm.conf.d
printf '[Theme]\nCurrent=breeze\n' | sudo tee /etc/sddm.conf.d/10-nimbus.conf >/dev/null

echo ":: Done. Lock screen is live now; SDDM applies at the next login screen."
