#!/usr/bin/env bash
# Layer 10 — Nimbus Flux: standalone bevy/wgpu GPU compute-shader fluid engine
# (the "wow ceiling" showpiece, separate from the desktop wallpaper). Builds the
# release binary and adds an app-menu launcher. Reversible via revert.sh.
# Runs as your normal user. Pass -y to skip the (single) confirmation.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CRATE="$HERE/nimbus-flux"
APPS="$HOME/.local/share/applications"
DESKTOP="$APPS/nimbus-flux.desktop"

ok(){   printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$1"; }

# 1. Rust toolchain (rustup installs to ~/.cargo; source it if PATH lacks cargo)
command -v cargo >/dev/null 2>&1 || { [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"; }
if ! command -v cargo >/dev/null 2>&1; then
  warn "cargo not found. Install Rust (user-local, reversible): "
  warn "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
  exit 1
fi

# 2. build the optimised binary
echo "  building release — the first build pulls ~400 crates, give it a few minutes…"
( cd "$CRATE" && cargo build --release ) || { warn "release build failed (see cargo output above)"; exit 1; }
ok "built → $CRATE/target/release/nimbus-flux"

# 3. app-menu launcher. Exec runs run.sh, which sets BEVY_ASSET_ROOT (so the
#    shader assets resolve) and prefers the release binary.
mkdir -p "$APPS"
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Nimbus Flux
GenericName=GPU Fluid Engine
Comment=GPU compute-shader fluid — drag to push, 1/2/3 ink·mercury·water, D light/dark
Exec=$HERE/run.sh
Icon=preferences-desktop-wallpaper
Terminal=false
Categories=Graphics;
EOF
ok "launcher installed → $DESKTOP  (search 'Nimbus Flux' in the app menu)"
echo "  or run directly:  bash $HERE/run.sh"
