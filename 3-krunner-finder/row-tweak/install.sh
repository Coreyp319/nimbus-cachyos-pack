#!/usr/bin/env bash
# Install the krunner-row-tweak (bold KRunner result rows) + pacman re-apply hook.
# Run as root:  sudo ~/.local/share/krunner-row-tweak/install.sh
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
CANON_DIR="/usr/local/share/krunner-row-tweak"
MILOU_DIR="/usr/lib/qt6/qml/org/kde/milou"
SYS_QML="$MILOU_DIR/ResultDelegate.qml"
QMLDIR="$MILOU_DIR/qmldir"
HOOK="/etc/pacman.d/hooks/krunner-row-tweak.hook"

if [[ $EUID -ne 0 ]]; then
  echo "This script must run as root. Try: sudo $0" >&2
  exit 1
fi

# Resolve the invoking user's home so we read the staged files even under sudo.
REAL_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
[[ -f "$SRC_DIR/ResultDelegate.qml" ]] || SRC_DIR="$REAL_HOME/.local/share/krunner-row-tweak"

echo "==> staging from: $SRC_DIR"
install -d "$CANON_DIR"

# Back up pristine originals exactly once.
[[ -f "$CANON_DIR/ResultDelegate.qml.orig" ]] || { cp "$MILOU_DIR/ResultDelegate.qml" "$CANON_DIR/ResultDelegate.qml.orig"; echo "==> backed up ResultDelegate.qml"; }
[[ -f "$CANON_DIR/ResultsView.qml.orig"   ]] || { cp "$MILOU_DIR/ResultsView.qml"   "$CANON_DIR/ResultsView.qml.orig";   echo "==> backed up ResultsView.qml"; }
[[ -f "$CANON_DIR/qmldir.orig"            ]] || { cp "$QMLDIR"                       "$CANON_DIR/qmldir.orig";            echo "==> backed up qmldir"; }

# Deploy canonical copies of our patched QML + the applier.
install -m644 "$SRC_DIR/ResultDelegate.qml" "$CANON_DIR/ResultDelegate.qml"
install -m644 "$SRC_DIR/ResultsView.qml"    "$CANON_DIR/ResultsView.qml"
install -m755 "$SRC_DIR/apply.sh"           "$CANON_DIR/apply.sh"

# Apply now (installs QML + strips the `prefer` line from qmldir).
"$CANON_DIR/apply.sh"
echo "==> applied patched delegate + removed qmldir 'prefer' redirect"

# Install the pacman hook so it survives milou upgrades.
install -d /etc/pacman.d/hooks
install -m644 "$SRC_DIR/krunner-row-tweak.hook" "$HOOK"
echo "==> installed pacman hook -> $HOOK"

# Restart KRunner (as the desktop user) after clearing any stale QML cache.
if [[ -n "${SUDO_USER:-}" ]]; then
  UID_OF=$(id -u "$SUDO_USER")
  run_user() { sudo -u "$SUDO_USER" XDG_RUNTIME_DIR="/run/user/$UID_OF" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_OF/bus" "$@"; }
  rm -rf "$REAL_HOME/.cache/krunner" "$REAL_HOME"/.cache/qmlcache/*milou* 2>/dev/null || true
  run_user kquitapp6 krunner 2>/dev/null || true
  echo "==> cleared QML cache + asked KRunner to quit (relaunches on next Alt+Space)"
fi

echo "DONE — open KRunner (Alt+Space) and search to see the new rows."
